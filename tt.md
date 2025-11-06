// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "@octant-core/core/BaseStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title YieldDonating Strategy - Kalani Vault
 * @author Octant Strategy Developer
 * @notice A production-ready YieldDonating strategy for Kalani vault on Base network
 * @dev Deposits USDC into Kalani ERC4626 vault, harvests yield, and donates 100% of profits
 *      to the configured donation address (Dragon Router).
 *
 *      ARCHITECTURE:
 *      - Deposits: All funds deployed to Kalani vault
 *      - Withdrawals: Intelligent withdrawal with liquidity checks
 *      - Tend: Deploys idle funds when threshold exceeded
 *      - Health Monitoring: Circuit breaker for vault failures
 *
 *      YIELD FLOW:
 *      User deposits USDC → Strategy → Kalani Vault
 *                              ↓
 *      Vault generates yield → report() → mints shares to donation address
 *
 *      NETWORK: Designed for Base network
 *      - Kalani Vault: ERC4626-compliant vault (0x7ea9FAC329636f532aE29E1c9EC9A964337bDA24)
 *      - Asset: USDC on Base (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
 */
interface IYieldSource {
    function asset() external view returns (address);
    function balanceOf(address) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
}

contract YieldDonatingStrategy is BaseStrategy {
    using SafeERC20 for ERC20;
    using Math for uint256;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Kalani vault address (ERC4626)
    IYieldSource public immutable yieldSource;

    /// @notice Minimum idle threshold to trigger deployment (in basis points of total assets)
    uint256 public minIdleThresholdBps = 100; // 1%

    /// @notice Vault health tracking
    struct VaultHealth {
        bool isPaused;
        uint256 consecutiveFailures;
        uint256 lastFailureTime;
    }

    VaultHealth public vaultHealth;

    /// @notice Maximum consecutive failures before pausing vault
    uint256 public constant MAX_CONSECUTIVE_FAILURES = 3;

    /// @notice Failure cooldown period
    uint256 public constant FAILURE_COOLDOWN = 1 hours;

    // ============================================
    // CONSTANTS
    // ============================================

    uint256 public constant MAX_BPS = 10_000;

    // ============================================
    // EVENTS
    // ============================================

    event FundsDeployed(uint256 amount, address yieldSource);
    event FundsWithdrawn(uint256 amount);
    event VaultPaused(address indexed vault, uint256 failures);
    event VaultResumed(address indexed vault);
    event EmergencyWithdrawal(uint256 amount);

    // ============================================
    // ERRORS
    // ============================================

    error VaultPausedError();
    error InvalidVaultAddress();
    error InsufficientLiquidity();

    /**
     * @notice Initializes the Kalani vault strategy
     * @param _yieldSource Address of Kalani ERC4626 vault
     * @param _asset Address of the underlying asset (USDC on Base)
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield (Dragon Router)
     * @param _enableBurning Whether loss-protection burning is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _yieldSource,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        // Validate vault address
        if (_yieldSource == address(0)) revert InvalidVaultAddress();

        yieldSource = IYieldSource(_yieldSource);

        // Verify vault uses the same asset
        if (yieldSource.asset() != _asset) {
            revert InvalidVaultAddress();
        }

        // Approve vault to spend strategy's assets
        ERC20(_asset).forceApprove(_yieldSource, type(uint256).max);

        // Initialize health status
        vaultHealth.isPaused = false;
    }

    // ============================================
    // CORE STRATEGY FUNCTIONS
    // ============================================

    /**
     * @notice Deploys funds to Kalani vault
     * @dev Respects vault pause status and health checks
     *      Implements try-catch for graceful failure handling
     * @param _amount Amount of assets to deploy
     */
    function _deployFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        // Check if vault is paused
        if (vaultHealth.isPaused) {
            revert VaultPausedError();
        }

        // Check vault capacity
        uint256 maxDeposit = yieldSource.maxDeposit(address(this));
        if (_amount > maxDeposit) {
            // Only deploy what vault can accept
            _amount = maxDeposit;
        }

        if (_amount == 0) return;

        // Deploy to vault with error handling
        try yieldSource.deposit(_amount, address(this)) {
            _resetVaultHealth();
            emit FundsDeployed(_amount, address(yieldSource));
        } catch {
            _handleVaultFailure(); // Keep funds idle if deposit fails
        }
    }

    /**
     * @notice Frees funds from Kalani vault for withdrawals
     * @dev Checks available liquidity before attempting withdrawal
     *      Uses try-catch for safe operation
     * @param _amount Amount of assets to free
     */
    function _freeFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        // Check if vault is paused
        if (vaultHealth.isPaused) {
            revert VaultPausedError();
        }

        // Check available liquidity
        uint256 availableLiquidity = _getAvailableLiquidity();
        if (availableLiquidity < _amount) {
            revert InsufficientLiquidity();
        }

        // Withdraw from vault
        uint256 withdrawn = _withdrawFromVault(_amount);
        emit FundsWithdrawn(withdrawn);
    }

    /**
     * @notice Harvests and reports total assets under management
     * @dev Aggregates vault assets plus idle funds
     *      This is the critical function for profit/loss calculation
     * @return _totalAssets Total assets managed by the strategy
     */
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // Get assets from vault (shares converted to assets)
        uint256 vaultAssets = _getVaultAssets();

        // Get idle assets in strategy
        uint256 idleAssets = asset.balanceOf(address(this));

        // Total = deployed + idle
        _totalAssets = vaultAssets + idleAssets;

        return _totalAssets;
    }

    // ============================================
    // OPTIONAL OVERRIDES
    // ============================================

    /**
     * @notice Returns maximum deposit limit
     * @dev Queries vault's max deposit capacity
     * @return Maximum additional assets that can be deposited
     */
    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        if (vaultHealth.isPaused) return 0;

        try yieldSource.maxDeposit(address(this)) returns (uint256 maxDeposit) {
            return maxDeposit;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Returns maximum withdrawal limit
     * @dev Sums available liquidity from vault plus idle funds
     * @return Maximum assets that can be withdrawn
     */
    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        uint256 idleAssets = asset.balanceOf(address(this));
        uint256 vaultLiquidity = _getAvailableLiquidity();

        return idleAssets + vaultLiquidity;
    }

    /**
     * @notice Performs maintenance between reports
     * @dev Deploys idle funds if above 1% threshold
     * @param _totalIdle Current amount of idle funds
     */
    function _tend(uint256 _totalIdle) internal override {
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        if (totalAssets == 0) return;

        // Deploy idle funds if above threshold (1% by default)
        uint256 idleThreshold = (totalAssets * minIdleThresholdBps) / MAX_BPS;
        if (_totalIdle > idleThreshold) {
            _deployFunds(_totalIdle);
        }
    }

    /**
     * @notice Determines if tend should be called
     * @dev Returns true if idle funds > 1% of total assets
     * @return shouldTend Whether tend should be called
     */
    function _tendTrigger() internal view override returns (bool) {
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        if (totalAssets == 0) return false;

        uint256 idleAssets = asset.balanceOf(address(this));

        // Trigger if idle funds above threshold
        uint256 idleThreshold = (totalAssets * minIdleThresholdBps) / MAX_BPS;
        return idleAssets > idleThreshold;
    }

    /**
     * @notice Emergency withdrawal after shutdown
     * @dev Withdraws all funds from vault
     * @param _amount Amount to withdraw (not used, withdraws everything)
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 withdrawn = 0;

        // Withdraw everything from vault
        if (!vaultHealth.isPaused) {
            uint256 shares = yieldSource.balanceOf(address(this));
            if (shares > 0) {
                try yieldSource.redeem(shares, address(this), address(this)) returns (uint256 assets) {
                    withdrawn = assets;
                } catch {
                    // Log failure but continue
                }
            }
        }

        emit EmergencyWithdrawal(withdrawn);
    }

    // ============================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Gets current assets deployed in vault
     * @dev Converts vault shares to assets
     * @return Assets in vault
     */
    function _getVaultAssets() internal view returns (uint256) {
        if (vaultHealth.isPaused) return 0;

        try yieldSource.balanceOf(address(this)) returns (uint256 shares) {
            if (shares == 0) return 0;

            try yieldSource.convertToAssets(shares) returns (uint256 assets) {
                return assets;
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }

    /**
     * @notice Gets available withdrawal liquidity from vault
     * @return Available liquidity
     */
    function _getAvailableLiquidity() internal view returns (uint256) {
        if (vaultHealth.isPaused) return 0;

        try yieldSource.maxWithdraw(address(this)) returns (uint256 maxWithdraw) {
            return maxWithdraw;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Withdraws assets from vault
     * @param _amount Amount to withdraw
     * @return Actual amount withdrawn
     */
    function _withdrawFromVault(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) return 0;

        try yieldSource.withdraw(_amount, address(this), address(this)) returns (uint256 shares) {
            _resetVaultHealth();
            return _amount; // ERC4626 withdraw returns shares, but we know the assets
        } catch {
            _handleVaultFailure();
            return 0;
        }
    }

    /**
     * @notice Handles vault failure and updates health status
     */
    function _handleVaultFailure() internal {
        vaultHealth.consecutiveFailures++;
        vaultHealth.lastFailureTime = block.timestamp;

        if (vaultHealth.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
            vaultHealth.isPaused = true;
            emit VaultPaused(address(yieldSource), vaultHealth.consecutiveFailures);
        }
    }

    /**
     * @notice Resets vault health on successful operation
     */
    function _resetVaultHealth() internal {
        if (vaultHealth.consecutiveFailures > 0) {
            vaultHealth.consecutiveFailures = 0;
            vaultHealth.lastFailureTime = 0;
        }
    }

    // ============================================
    // MANAGEMENT FUNCTIONS
    // ============================================

    /**
     * @notice Manually resumes a paused vault
     * @dev Only callable by management
     */
    function resumeVault() external onlyManagement {
        vaultHealth.isPaused = false;
        vaultHealth.consecutiveFailures = 0;
        vaultHealth.lastFailureTime = 0;
        emit VaultResumed(address(yieldSource));
    }

    /**
     * @notice Sets minimum idle threshold
     * @param _thresholdBps Threshold in basis points (max 10%)
     */
    function setMinIdleThreshold(uint256 _thresholdBps) external onlyManagement {
        require(_thresholdBps <= 1000, "Threshold too high"); // Max 10%
        minIdleThresholdBps = _thresholdBps;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Returns detailed breakdown of assets
     * @return vault Assets in vault
     * @return idle Idle assets in strategy
     * @return total Total assets
     */
    function getAssetBreakdown() external view returns (uint256 vault, uint256 idle, uint256 total) {
        vault = _getVaultAssets();
        idle = asset.balanceOf(address(this));
        total = vault + idle;
    }

    /**
     * @notice Returns vault health status
     * @return isPaused Whether vault is paused
     * @return failures Consecutive failures
     * @return lastFailure Timestamp of last failure
     */
    function getVaultHealth() external view returns (bool isPaused, uint256 failures, uint256 lastFailure) {
        return (vaultHealth.isPaused, vaultHealth.consecutiveFailures, vaultHealth.lastFailureTime);
    }
}