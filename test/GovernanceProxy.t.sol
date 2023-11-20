// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";

import "../contracts/access/GovernanceProxy.sol";

contract Governed {
    uint256 public value;

    function setValue(uint256 n) external {
        value = n;
    }
}

contract GovernanceProxyTest is Test {
    GovernanceProxy public governanceProxy;
    Governed public governed;

    address public governance = makeAddr("governance");
    address public veto = makeAddr("veto");

    function setUp() public {
        governanceProxy = new GovernanceProxy(governance, veto);
        governed = new Governed();
    }

    function testRequestImmediateChange() external {
        vm.prank(governance);
        governanceProxy.requestChange(_makeSetValueCall(3));
        assertEq(governed.value(), 3);
    }

    function _makeSetValueCall(
        uint256 value
    ) internal view returns (IGovernanceProxy.Call[] memory calls) {
        calls = new IGovernanceProxy.Call[](1);
        calls[0] = IGovernanceProxy.Call({
            target: address(governed),
            data: abi.encodeWithSelector(Governed.setValue.selector, value)
        });
    }

    function _makeCall(
        address target,
        bytes memory data
    ) internal pure returns (IGovernanceProxy.Call[] memory calls) {
        calls = new IGovernanceProxy.Call[](1);
        calls[0] = IGovernanceProxy.Call({target: target, data: data});
    }
}
