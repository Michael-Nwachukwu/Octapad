// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.11.0/src/Test.sol";
import {console} from "forge-std-1.11.0/src/console.sol";
import {OGPointsToken} from "../src/launchpad/OGPointsToken.sol";

contract OGPointsTokenTest is Test {
    OGPointsToken public token;

    address public admin = address(0x1);
    address public minter1 = address(0x2);
    address public minter2 = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event PointsMinted(address indexed to, uint256 amount, address indexed minter);
    event PointsBurned(address indexed from, uint256 amount);

    function setUp() public {
        vm.prank(admin);
        token = new OGPointsToken(
            "OctaPad OG Points",
            "OG",
            admin,
            true // isNonTransferable
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public {
        assertEq(token.name(), "OctaPad OG Points");
        assertEq(token.symbol(), "OG");
        assertEq(token.admin(), admin);
        assertEq(token.isNonTransferable(), true);
        assertEq(token.totalSupply(), 0);
    }

    function test_DeploymentTransferable() public {
        vm.prank(admin);
        OGPointsToken transferableToken = new OGPointsToken(
            "Transferable Points",
            "TP",
            admin,
            false // isNonTransferable = false
        );

        assertEq(transferableToken.isNonTransferable(), false);
    }

    function testRevert_DeploymentZeroAdmin() public {
        vm.expectRevert("OGPointsToken: zero admin");
        new OGPointsToken("Test", "TST", address(0), true);
    }

    /*//////////////////////////////////////////////////////////////
                        MINTER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddMinter() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit MinterAdded(minter1);
        token.addMinter(minter1);

        assertTrue(token.isMinter(minter1));
    }

    function test_AddMultipleMinters() public {
        vm.startPrank(admin);
        token.addMinter(minter1);
        token.addMinter(minter2);
        vm.stopPrank();

        assertTrue(token.isMinter(minter1));
        assertTrue(token.isMinter(minter2));
    }

    function testRevert_AddMinterUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(OGPointsToken.Unauthorized.selector);
        token.addMinter(minter1);
    }

    function testRevert_AddMinterZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("OGPointsToken: zero minter");
        token.addMinter(address(0));
    }

    function testRevert_AddMinterAlreadyMinter() public {
        vm.startPrank(admin);
        token.addMinter(minter1);

        vm.expectRevert("OGPointsToken: already minter");
        token.addMinter(minter1);
        vm.stopPrank();
    }

    function test_RemoveMinter() public {
        vm.startPrank(admin);
        token.addMinter(minter1);

        vm.expectEmit(true, false, false, false);
        emit MinterRemoved(minter1);
        token.removeMinter(minter1);
        vm.stopPrank();

        assertFalse(token.isMinter(minter1));
    }

    function testRevert_RemoveMinterUnauthorized() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.prank(user1);
        vm.expectRevert(OGPointsToken.Unauthorized.selector);
        token.removeMinter(minter1);
    }

    function testRevert_RemoveMinterNotMinter() public {
        vm.prank(admin);
        vm.expectRevert("OGPointsToken: not minter");
        token.removeMinter(minter1);
    }

    /*//////////////////////////////////////////////////////////////
                        MINTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.prank(minter1);
        vm.expectEmit(true, false, false, true);
        emit PointsMinted(user1, 1000e18, minter1);
        token.mint(user1, 1000e18);

        assertEq(token.balanceOf(user1), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
        assertEq(token.totalMinted(), 1000e18);
        assertEq(token.userMinted(user1), 1000e18);
    }

    function test_MintMultipleUsers() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.startPrank(minter1);
        token.mint(user1, 500e18);
        token.mint(user2, 300e18);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 500e18);
        assertEq(token.balanceOf(user2), 300e18);
        assertEq(token.totalSupply(), 800e18);
        assertEq(token.totalMinted(), 800e18);
    }

    function test_MintFromMultipleMinters() public {
        vm.startPrank(admin);
        token.addMinter(minter1);
        token.addMinter(minter2);
        vm.stopPrank();

        vm.prank(minter1);
        token.mint(user1, 500e18);

        vm.prank(minter2);
        token.mint(user1, 300e18);

        assertEq(token.balanceOf(user1), 800e18);
        assertEq(token.userMinted(user1), 800e18);
    }

    function testRevert_MintUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(OGPointsToken.Unauthorized.selector);
        token.mint(user2, 1000e18);
    }

    function testRevert_MintZeroAmount() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.prank(minter1);
        vm.expectRevert(OGPointsToken.InvalidAmount.selector);
        token.mint(user1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        BURNING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Burn() public {
        // Setup: mint some tokens
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 1000e18);

        // User burns their own tokens
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit PointsBurned(user1, 400e18);
        token.burn(400e18);

        assertEq(token.balanceOf(user1), 600e18);
        assertEq(token.totalSupply(), 600e18);
        assertEq(token.totalBurned(), 400e18);
        assertEq(token.userBurned(user1), 400e18);
    }

    function test_BurnAll() public {
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        token.burn(1000e18);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.totalSupply(), 0);
        assertEq(token.totalBurned(), 1000e18);
    }

    function testRevert_BurnZeroAmount() public {
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        vm.expectRevert(OGPointsToken.InvalidAmount.selector);
        token.burn(0);
    }

    function testRevert_BurnInsufficientBalance() public {
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 100e18);

        vm.prank(user1);
        vm.expectRevert(); // ERC20 InsufficientBalance
        token.burn(200e18);
    }

    function test_BurnFrom() public {
        // Setup
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 1000e18);

        // Minter burns from user (for redemption mechanisms)
        vm.prank(minter1);
        token.burnFrom(user1, 300e18);

        assertEq(token.balanceOf(user1), 700e18);
        assertEq(token.totalBurned(), 300e18);
        assertEq(token.userBurned(user1), 300e18);
    }

    function testRevert_BurnFromUnauthorized() public {
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user2);
        vm.expectRevert(OGPointsToken.Unauthorized.selector);
        token.burnFrom(user1, 300e18);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER RESTRICTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_TransferWhenNonTransferable() public {
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        vm.expectRevert(OGPointsToken.TransferDisabled.selector);
        token.transfer(user2, 500e18);
    }

    function testRevert_TransferFromWhenNonTransferable() public {
        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        token.approve(user2, 500e18);

        vm.prank(user2);
        vm.expectRevert(OGPointsToken.TransferDisabled.selector);
        token.transferFrom(user1, user2, 500e18);
    }

    function test_TransferWhenTransferable() public {
        // Deploy transferable token
        vm.prank(admin);
        OGPointsToken transferableToken = new OGPointsToken(
            "Transferable",
            "TRANS",
            admin,
            false
        );

        vm.prank(admin);
        transferableToken.addMinter(minter1);
        vm.prank(minter1);
        transferableToken.mint(user1, 1000e18);

        vm.prank(user1);
        transferableToken.transfer(user2, 500e18);

        assertEq(transferableToken.balanceOf(user1), 500e18);
        assertEq(transferableToken.balanceOf(user2), 500e18);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferAdmin() public {
        address newAdmin = address(0x999);

        vm.prank(admin);
        token.transferAdmin(newAdmin);

        assertEq(token.admin(), newAdmin);
    }

    function testRevert_TransferAdminUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(OGPointsToken.Unauthorized.selector);
        token.transferAdmin(user2);
    }

    function testRevert_TransferAdminZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("OGPointsToken: zero admin");
        token.transferAdmin(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetUserStats() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        token.burn(300e18);

        (uint256 balance, uint256 minted, uint256 burned) = token.getUserStats(user1);

        assertEq(balance, 700e18);
        assertEq(minted, 1000e18);
        assertEq(burned, 300e18);
    }

    function test_GetGlobalStats() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.startPrank(minter1);
        token.mint(user1, 1000e18);
        token.mint(user2, 500e18);
        vm.stopPrank();

        vm.prank(user1);
        token.burn(200e18);

        (uint256 totalSupply_, uint256 totalMinted_, uint256 totalBurned_) = token.getGlobalStats();

        assertEq(totalSupply_, 1300e18); // 1500 - 200
        assertEq(totalMinted_, 1500e18);
        assertEq(totalBurned_, 200e18);
    }

    function test_GetNetPoints() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        token.burn(300e18);

        uint256 netPoints = token.getNetPoints(user1);
        assertEq(netPoints, 700e18); // 1000 - 300
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(uint128 amount) public {
        vm.assume(amount > 0);

        vm.prank(admin);
        token.addMinter(minter1);

        vm.prank(minter1);
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testFuzz_Burn(uint128 mintAmount, uint128 burnAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(burnAmount > 0);
        vm.assume(burnAmount <= mintAmount);

        vm.prank(admin);
        token.addMinter(minter1);
        vm.prank(minter1);
        token.mint(user1, mintAmount);

        vm.prank(user1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user1), mintAmount - burnAmount);
        assertEq(token.totalBurned(), burnAmount);
    }

    function testFuzz_MultipleMints(uint8 numMints) public {
        vm.assume(numMints > 0 && numMints <= 50);

        vm.prank(admin);
        token.addMinter(minter1);

        uint256 totalMinted;
        for (uint256 i = 0; i < numMints; i++) {
            uint256 amount = 100e18 * (i + 1);
            vm.prank(minter1);
            token.mint(user1, amount);
            totalMinted += amount;
        }

        assertEq(token.balanceOf(user1), totalMinted);
        assertEq(token.totalSupply(), totalMinted);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintAfterBurn() public {
        vm.prank(admin);
        token.addMinter(minter1);

        vm.prank(minter1);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        token.burn(500e18);

        vm.prank(minter1);
        token.mint(user1, 300e18);

        assertEq(token.balanceOf(user1), 800e18);
        assertEq(token.userMinted(user1), 1300e18);
        assertEq(token.userBurned(user1), 500e18);
    }

    function test_MultipleUsersComplexScenario() public {
        vm.prank(admin);
        token.addMinter(minter1);

        // Mint to multiple users
        vm.startPrank(minter1);
        token.mint(user1, 1000e18);
        token.mint(user2, 500e18);
        vm.stopPrank();

        // Users burn different amounts
        vm.prank(user1);
        token.burn(200e18);

        vm.prank(user2);
        token.burn(100e18);

        // Check final state
        assertEq(token.balanceOf(user1), 800e18);
        assertEq(token.balanceOf(user2), 400e18);
        assertEq(token.totalSupply(), 1200e18);
        assertEq(token.totalMinted(), 1500e18);
        assertEq(token.totalBurned(), 300e18);
    }
}
