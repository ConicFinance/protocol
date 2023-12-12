// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../libraries/ArrayExtensions.sol";

contract ArrayExtensionsTest is Test {
    function testRemoveDuplicates() public {
        address[] memory array = new address[](5);
        array[0] = address(1);
        array[1] = address(2);
        array[2] = address(0);
        array[3] = address(1);
        array[4] = address(1);
        address[] memory unique = ArrayExtensions.removeDuplicates(array);
        assertEq(unique.length, 3);
        assertEq(unique[0], address(1));
        assertEq(unique[1], address(2));
        assertEq(unique[2], address(0));
    }
}
