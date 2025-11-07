// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.25;

// import {Test} from "forge-std-1.11.0/src/Test.sol";
// import {console} from "forge-std-1.11.0/src/console.sol";
// import {OGPointsRewards} from "../src/launchpad/OGPointsRewards.sol";
// import {OGPointsToken} from "../src/launchpad/OGPointsToken.sol";
// import {PaymentSplitter} from "@octant-core/core/PaymentSplitter.sol";
// import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";

// // Mock ERC20 for testing
// contract MockERC20 is IERC20 {
//     mapping(address => uint256) private _balances;
//     mapping(address => mapping(address => uint256)) private _allowances;
//     uint256 private _totalSupply;
//     string public name = "Mock USDC";
//     string public symbol = "MUSDC";
//     uint8 public decimals = 6;

//     function totalSupply() external view override returns (uint256) {
//         return _totalSupply;
//     }

//     function balanceOf(address account) external view override returns (uint256) {
//         return _balances[account];
//     }

//     function transfer(address to, uint256 amount) external override returns (bool) {
//         _transfer(msg.sender, to, amount);
//         return true;
//     }

//     function allowance(address owner, address spender) external view override returns (uint256) {
//         return _allowances[owner][spender];
//     }

//     function approve(address spender, uint256 amount) external override returns (bool) {
//         _allowances[msg.sender][spender] = amount;
//         return true;
//     }

//     function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
//         require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
//         _allowances[from][msg.sender] -= amount;
//         _transfer(from, to, amount);
//         return true;
//     }

//     function _transfer(address from, address to, uint256 amount) internal {
//         require(_balances[from] >= amount, "Insufficient balance");
//         _balances[from] -= amount;
//         _balances[to] += amount;
//     }

//     function mint(address to, uint256 amount) external {
//         _balances[to] += amount;
//         _totalSupply += amount;
//     }
// }

// // Mock YieldDonatingStrategy for testing
// contract MockYieldStrategy is IERC20 {
//     MockERC20 public usdc;
//     mapping(address => uint256) private _shares;
//     uint256 private _totalShares;
//     uint256 public totalAssets;

//     constructor(address _usdc) {
//         usdc = MockERC20(_usdc);
//     }

//     function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
//         usdc.transferFrom(msg.sender, address(this), assets);
//         shares = assets; // 1:1 for simplicity
//         _shares[receiver] += shares;
//         _totalShares += shares;
//         totalAssets += assets;
//         return shares;
//     }

//     function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
//         require(_shares[owner] >= shares, "Insufficient shares");
//         _shares[owner] -= shares;
//         _totalShares -= shares;
//         assets = shares; // 1:1 for simplicity
//         totalAssets -= assets;
//         usdc.transfer(receiver, assets);
//         return assets;
//     }

//     function balanceOf(address account) external view override returns (uint256) {
//         return _shares[account];
//     }

//     function totalSupply() external view override returns (uint256) {
//         return _totalShares;
//     }

//     function transfer(address to, uint256 amount) external override returns (bool) {
//         require(_shares[msg.sender] >= amount, "Insufficient balance");
//         _shares[msg.sender] -= amount;
//         _shares[to] += amount;
//         return true;
//     }

//     function allowance(address, address) external pure override returns (uint256) {
//         return 0;
//     }

//     function approve(address, uint256) external pure override returns (bool) {
//         return true;
//     }

//     function transferFrom(address, address, uint256) external pure override returns (bool) {
//         revert("Not implemented");
//     }
// }

// contract OGPointsRewardsTest is Test {
//     OGPointsRewards public rewards;
//     OGPointsToken public ogToken;
//     MockERC20 public usdc;
//     MockYieldStrategy public strategy;
//     PaymentSplitter public splitter;

//     address public admin = address(0x1);
//     address public dragonRouter = address(0x2);
//     address public user1 = address(0x3);
//     address public user2 = address(0x4);
//     address public user3 = address(0x5);

//     function setUp() public {
//         // Deploy mock USDC
//         usdc = new MockERC20();

//         // Deploy mock strategy
//         strategy = new MockYieldStrategy(address(usdc));

//         // Deploy OG Points Token
//         vm.prank(admin);
//         ogToken = new OGPointsToken("OG Points", "OG", admin, true);

//         // Deploy PaymentSplitter
//         splitter = new PaymentSplitter();
//         address[] memory payees = new address[](2);
//         payees[0] = dragonRouter;
//         payees[1] = address(this); // Temporary, will be updated

//         uint256[] memory shares = new uint256[](2);
//         shares[0] = 50;
//         shares[1] = 50;

//         splitter.initialize(payees, shares);

//         // Deploy OGPointsRewards
//         vm.prank(admin);
//         rewards = new OGPointsRewards(
//             address(ogToken),
//             address(usdc),
//             admin,
//             address(0), // rewardsDistributor (optional)
//             address(strategy),
//             address(splitter)
//         );

//         // Add rewards contract as minter for OG Points
//         vm.prank(admin);
//         ogToken.addMinter(address(rewards));

//         // Give users some OG Points
//         vm.startPrank(admin);
//         ogToken.addMinter(admin);
//         ogToken.mint(user1, 1000e18);
//         ogToken.mint(user2, 500e18);
//         ogToken.mint(user3, 250e18);
//         vm.stopPrank();
//     }

//     /*//////////////////////////////////////////////////////////////
//                         DEPLOYMENT TESTS
//     //////////////////////////////////////////////////////////////*/

//     function test_Deployment() public {
//         assertEq(address(rewards.ogPointsToken()), address(ogToken));
//         assertEq(address(rewards.usdc()), address(usdc));
//         assertEq(address(rewards.yieldStrategy()), address(strategy));
//         assertEq(address(rewards.paymentSplitter()), address(splitter));
//         assertEq(rewards.admin(), admin);
//     }

//     function testRevert_DeploymentZeroAddresses() public {
//         vm.startPrank(admin);

//         vm.expectRevert("OGPointsRewards: zero points token");
//         new OGPointsRewards(address(0), address(usdc), admin, address(0), address(strategy), address(splitter));

//         vm.expectRevert("OGPointsRewards: zero usdc");
//         new OGPointsRewards(address(ogToken), address(0), admin, address(0), address(strategy), address(splitter));

//         vm.expectRevert("OGPointsRewards: zero admin");
//         new OGPointsRewards(address(ogToken), address(usdc), address(0), address(0), address(strategy), address(splitter));

//         vm.expectRevert("OGPointsRewards: zero strategy");
//         new OGPointsRewards(address(ogToken), address(usdc), admin, address(0), address(0), address(splitter));

//         vm.expectRevert("OGPointsRewards: zero splitter");
//         new OGPointsRewards(address(ogToken), address(usdc), admin, address(0), address(strategy), address(0));

//         vm.stopPrank();
//     }

//     /*//////////////////////////////////////////////////////////////
//                     CLAIM AND REDEEM FROM SPLITTER TESTS
//     //////////////////////////////////////////////////////////////*/

//     function test_ClaimAndRedeemFromSplitter() public {
//         // Setup: Strategy earns profit and mints shares to splitter
//         usdc.mint(address(strategy), 1000e6); // 1000 USDC profit
//         strategy.deposit(1000e6, address(splitter));

//         // Splitter now has 1000 strategy shares
//         // 50% (500 shares) should be claimable by rewards contract

//         // Check claimable amount
//         uint256 claimable = rewards.getClaimableShares();
//         assertEq(claimable, 500e6); // 50% of 1000

//         // Claim and redeem
//         rewards.claimAndRedeemFromSplitter();

//         // Check that rewards were distributed
//         assertTrue(rewards.rewardsPerPoint() > 0);

//         // Total OG Points = 1750e18 (1000 + 500 + 250)
//         // Rewards = 500 USDC (6 decimals)
//         // Expected rewardsPerPoint = (500e6 * 1e18) / 1750e18 = 285714285714
//         uint256 totalPoints = 1750e18;
//         uint256 rewardAmount = 500e6;
//         uint256 expectedRpp = (rewardAmount * 1e18) / totalPoints;
//         assertEq(rewards.rewardsPerPoint(), expectedRpp);
//     }

//     function test_ClaimAndRedeemMultipleTimes() public {
//         // First profit
//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         uint256 rppAfterFirst = rewards.rewardsPerPoint();

//         // Second profit
//         usdc.mint(address(strategy), 500e6);
//         strategy.deposit(500e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         uint256 rppAfterSecond = rewards.rewardsPerPoint();

//         // Rewards per point should have increased
//         assertTrue(rppAfterSecond > rppAfterFirst);
//     }

//     function test_ClaimAndRedeemWithNoPointHolders() public {
//         // Remove all points
//         vm.prank(user1);
//         ogToken.burn(ogToken.balanceOf(user1));
//         vm.prank(user2);
//         ogToken.burn(ogToken.balanceOf(user2));
//         vm.prank(user3);
//         ogToken.burn(ogToken.balanceOf(user3));

//         // Setup profit
//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));

//         // Claim and redeem
//         rewards.claimAndRedeemFromSplitter();

//         // Should accumulate in pending rewards
//         assertEq(rewards.pendingRewards(), 500e6);
//     }

//     function testRevert_ClaimAndRedeemWithNoShares() public {
//         // Try to claim when splitter has no shares
//         vm.expectRevert();
//         rewards.claimAndRedeemFromSplitter();
//     }

//     /*//////////////////////////////////////////////////////////////
//                         REWARDS CLAIMING TESTS
//     //////////////////////////////////////////////////////////////*/

//     function test_ClaimRewards() public {
//         // Setup: Distribute rewards
//         usdc.mint(address(strategy), 1750e6); // Exact amount for 1:1 distribution
//         strategy.deposit(1750e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // User1 has 1000 points out of 1750 total
//         // Should get (1000/1750) * 875 USDC = 500 USDC
//         uint256 expectedReward = (1000e18 * 875e6) / 1750e18;

//         uint256 pendingBefore = rewards.getPendingRewards(user1);
//         assertEq(pendingBefore, expectedReward);

//         vm.prank(user1);
//         rewards.claimRewards();

//         assertEq(usdc.balanceOf(user1), expectedReward);
//         assertEq(rewards.getPendingRewards(user1), 0);
//     }

//     function test_ClaimRewardsMultipleUsers() public {
//         usdc.mint(address(strategy), 1750e6);
//         strategy.deposit(1750e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // User1 claims
//         vm.prank(user1);
//         rewards.claimRewards();

//         // User2 claims
//         vm.prank(user2);
//         rewards.claimRewards();

//         // User3 claims
//         vm.prank(user3);
//         rewards.claimRewards();

//         // Check balances proportional to points
//         assertTrue(usdc.balanceOf(user1) > usdc.balanceOf(user2));
//         assertTrue(usdc.balanceOf(user2) > usdc.balanceOf(user3));
//     }

//     function testRevert_ClaimRewardsNoPending() public {
//         vm.prank(user1);
//         vm.expectRevert(OGPointsRewards.NoRewardsToClaim.selector);
//         rewards.claimRewards();
//     }

//     function test_ClaimRewardsAfterBurningPoints() public {
//         // Setup rewards
//         usdc.mint(address(strategy), 1750e6);
//         strategy.deposit(1750e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // User1 burns half their points
//         vm.prank(user1);
//         ogToken.burn(500e18);

//         // Claim rewards (should get rewards for original 1000 points)
//         uint256 expectedReward = (1000e18 * 875e6) / 1750e18;

//         vm.prank(user1);
//         rewards.claimRewards();

//         assertEq(usdc.balanceOf(user1), expectedReward);
//     }

//     /*//////////////////////////////////////////////////////////////
//                     DISTRIBUTE PENDING REWARDS TESTS
//     //////////////////////////////////////////////////////////////*/

//     function test_DistributePendingRewards() public {
//         // Accumulate rewards with no point holders
//         vm.prank(user1);
//         ogToken.burn(ogToken.balanceOf(user1));
//         vm.prank(user2);
//         ogToken.burn(ogToken.balanceOf(user2));
//         vm.prank(user3);
//         ogToken.burn(ogToken.balanceOf(user3));

//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         assertEq(rewards.pendingRewards(), 500e6);

//         // Mint new points to user1
//         vm.prank(admin);
//         ogToken.mint(user1, 100e18);

//         // Distribute pending rewards
//         rewards.distributePendingRewards();

//         assertEq(rewards.pendingRewards(), 0);
//         assertTrue(rewards.rewardsPerPoint() > 0);
//     }

//     function testRevert_DistributePendingRewardsNoHolders() public {
//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // Burn all points
//         vm.prank(user1);
//         ogToken.burn(ogToken.balanceOf(user1));
//         vm.prank(user2);
//         ogToken.burn(ogToken.balanceOf(user2));
//         vm.prank(user3);
//         ogToken.burn(ogToken.balanceOf(user3));

//         vm.expectRevert(OGPointsRewards.NoPointHolders.selector);
//         rewards.distributePendingRewards();
//     }

//     /*//////////////////////////////////////////////////////////////
//                         VIEW FUNCTIONS TESTS
//     //////////////////////////////////////////////////////////////*/

//     function test_GetPendingRewards() public {
//         usdc.mint(address(strategy), 1750e6);
//         strategy.deposit(1750e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         uint256 user1Pending = rewards.getPendingRewards(user1);
//         uint256 user2Pending = rewards.getPendingRewards(user2);

//         assertTrue(user1Pending > user2Pending);
//         assertEq(user1Pending, (1000e18 * 875e6) / 1750e18);
//     }

//     function test_GetUserStats() public {
//         usdc.mint(address(strategy), 1750e6);
//         strategy.deposit(1750e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         (uint256 points, uint256 pending, uint256 claimed) = rewards.getUserStats(user1);

//         assertEq(points, 1000e18);
//         assertTrue(pending > 0);
//         assertEq(claimed, 0);

//         vm.prank(user1);
//         rewards.claimRewards();

//         (, , claimed) = rewards.getUserStats(user1);
//         assertTrue(claimed > 0);
//     }

//     function test_GetGlobalStats() public {
//         usdc.mint(address(strategy), 1750e6);
//         strategy.deposit(1750e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         (
//             uint256 totalPoints,
//             uint256 rpp,
//             uint256 totalDeposited,
//             uint256 totalClaimed,
//             uint256 pending
//         ) = rewards.getGlobalStats();

//         assertEq(totalPoints, 1750e18);
//         assertTrue(rpp > 0);
//         assertEq(totalDeposited, 875e6); // 50% of 1750
//         assertEq(totalClaimed, 0);
//         assertEq(pending, 0);
//     }

//     function test_GetUserSharePercentage() public {
//         uint256 user1Share = rewards.getUserSharePercentage(user1);
//         uint256 user2Share = rewards.getUserSharePercentage(user2);

//         // User1: 1000/1750 = 57.14%
//         uint256 user1Points = 1000e18;
//         uint256 totalPoints2 = 1750e18;
//         uint256 expectedUser1Share = (user1Points * 1e18) / totalPoints2;
//         assertEq(user1Share, expectedUser1Share);
//         // User2: 500/1750 = 28.57%
//         uint256 user2Points = 500e18;
//         uint256 expectedUser2Share = (user2Points * 1e18) / totalPoints2;
//         assertEq(user2Share, expectedUser2Share);
//     }

//     function test_GetClaimableShares() public {
//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));

//         uint256 claimable = rewards.getClaimableShares();
//         assertEq(claimable, 500e6); // 50% of 1000
//     }

//     function test_GetHeldShares() public {
//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));

//         // Initially no held shares
//         assertEq(rewards.getHeldShares(), 0);

//         // After claiming, should have shares
//         rewards.claimAndRedeemFromSplitter();

//         // Shares were redeemed, so should be 0 again
//         assertEq(rewards.getHeldShares(), 0);
//     }

//     /*//////////////////////////////////////////////////////////////
//                         COMPLEX SCENARIO TESTS
//     //////////////////////////////////////////////////////////////*/

//     function test_MultipleDistributionsAndClaims() public {
//         // First distribution
//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // User1 claims
//         vm.prank(user1);
//         rewards.claimRewards();
//         uint256 user1FirstClaim = usdc.balanceOf(user1);

//         // Second distribution
//         usdc.mint(address(strategy), 2000e6);
//         strategy.deposit(2000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // User1 claims again
//         vm.prank(user1);
//         rewards.claimRewards();
//         uint256 user1SecondClaim = usdc.balanceOf(user1);

//         // Second claim should be larger (more rewards distributed)
//         assertTrue(user1SecondClaim > user1FirstClaim);
//     }

//     function test_NewUserJoinsAfterDistribution() public {
//         // First distribution
//         usdc.mint(address(strategy), 1000e6);
//         strategy.deposit(1000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // New user gets points
//         address newUser = address(0x999);
//         vm.prank(admin);
//         ogToken.mint(newUser, 1000e18);

//         // New user should not get rewards from first distribution
//         assertEq(rewards.getPendingRewards(newUser), 0);

//         // Second distribution
//         usdc.mint(address(strategy), 2000e6);
//         strategy.deposit(2000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // New user should get rewards from second distribution
//         assertTrue(rewards.getPendingRewards(newUser) > 0);
//     }

//     /*//////////////////////////////////////////////////////////////
//                         FUZZ TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testFuzz_ClaimAndRedeem(uint128 profitAmount) public {
//         vm.assume(profitAmount > 1000);
//         vm.assume(profitAmount < 1000000e6);

//         usdc.mint(address(strategy), profitAmount);
//         strategy.deposit(profitAmount, address(splitter));

//         uint256 claimableBefore = rewards.getClaimableShares();
//         rewards.claimAndRedeemFromSplitter();

//         // Should have distributed half the profit
//         assertTrue(rewards.totalRewardsDeposited() > 0);
//         assertEq(rewards.getClaimableShares(), 0);
//     }

//     function testFuzz_MultipleUserClaims(uint8 numUsers) public {
//         vm.assume(numUsers > 0 && numUsers <= 20);

//         // Setup: Give points to users
//         for (uint256 i = 0; i < numUsers; i++) {
//             address user = address(uint160(0x1000 + i));
//             vm.prank(admin);
//             ogToken.mint(user, 100e18);
//         }

//         // Distribute rewards
//         usdc.mint(address(strategy), 10000e6);
//         strategy.deposit(10000e6, address(splitter));
//         rewards.claimAndRedeemFromSplitter();

//         // All users claim
//         uint256 totalClaimed;
//         for (uint256 i = 0; i < numUsers; i++) {
//             address user = address(uint160(0x1000 + i));
//             uint256 pending = rewards.getPendingRewards(user);
//             if (pending > 0) {
//                 vm.prank(user);
//                 rewards.claimRewards();
//                 totalClaimed += usdc.balanceOf(user);
//             }
//         }

//         // Total claimed should equal total distributed (minus rounding)
//         assertApproxEqRel(totalClaimed, 5000e6, 0.01e18); // Within 1%
//     }
// }
