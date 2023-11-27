// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../contracts/LpToken.sol";

contract FakeController {
    address public immutable creator;
    mapping(address => bool) public _authorized;
    uint256 internal _minimumTaintedTransferAmount;

    constructor() {
        creator = msg.sender;
    }

    function setAuthorized(address account, bool value) external {
        _authorized[account] = value;
    }

    function setMinimumTaintedTransferAmount(uint256 value) external {
        _minimumTaintedTransferAmount = value;
    }

    function getMinimumTaintedTransferAmount(address) external view returns (uint256) {
        return _minimumTaintedTransferAmount;
    }

    function isAllowedMultipleDepositsWithdraws(address account) external view returns (bool) {
        return _authorized[account];
    }

    function lpTokenStaker() external view returns (address) {
        return creator;
    }
}

contract LpTokenTest is Test {
    FakeController public controller;
    ILpToken public lpToken;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        controller = new FakeController();
        lpToken = new LpToken(address(controller), address(this), 18, "Test LP Token", "TLP");
        controller.setMinimumTaintedTransferAmount(1e18);
    }

    function testMintUnderThreshold() public {
        lpToken.mint(alice, 0.5e18, alice);
        lpToken.mint(alice, 0.5e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);
    }

    function testMintOverThreshold() public {
        lpToken.mint(alice, 2e18, alice);
        assertEq(lpToken.balanceOf(alice), 2e18);
        vm.expectRevert("cannot mint/burn twice in a block");
        lpToken.mint(alice, 2e18, alice);
    }

    function testMintBurnUnderThreshold() public {
        lpToken.mint(alice, 0.5e18, alice);
        assertEq(lpToken.balanceOf(alice), 0.5e18);
        lpToken.burn(alice, 0.5e18, alice);
        assertEq(lpToken.balanceOf(alice), 0);
    }

    function testMintBurnOverThreshold() public {
        lpToken.mint(alice, 2e18, alice);
        assertEq(lpToken.balanceOf(alice), 2e18);
        vm.expectRevert("cannot mint/burn twice in a block");
        lpToken.burn(alice, 2e18, alice);
    }

    function testMintTransferUnderThreshold() public {
        lpToken.mint(alice, 2e18, alice);
        vm.prank(alice);
        lpToken.transfer(bob, 0.5e18);
        assertEq(lpToken.balanceOf(bob), 0.5e18);
        lpToken.burn(bob, 0.5e18, bob);
    }

    function testMintTransferOverThreshold() public {
        lpToken.mint(alice, 2e18, alice);
        vm.prank(alice);
        lpToken.transfer(bob, 2e18);
        assertEq(lpToken.balanceOf(bob), 2e18);
        vm.expectRevert("cannot mint/burn twice in a block");
        lpToken.burn(bob, 2e18, bob);
    }

    function testTaintUnderThreshold() public {
        lpToken.mint(alice, 0.5e18, alice);
        lpToken.taint(alice, bob, 0.5e18);
        lpToken.mint(bob, 0.5e18, bob);
        assertEq(lpToken.balanceOf(bob), 0.5e18);
    }

    function testTaintOverThreshold() public {
        lpToken.mint(alice, 2e18, alice);
        lpToken.taint(alice, bob, 2e18);
        vm.expectRevert("cannot mint/burn twice in a block");
        lpToken.mint(bob, 2e18, bob);
    }

    function testMultipleMintAuthorizedUBO() public {
        controller.setAuthorized(alice, true);
        lpToken.mint(alice, 2e18, alice);
        lpToken.mint(alice, 2e18, alice);
        assertEq(lpToken.balanceOf(alice), 4e18);
    }
}
