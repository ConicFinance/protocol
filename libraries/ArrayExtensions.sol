// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

library ArrayExtensions {
    function copy(uint256[] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory copy_ = new uint256[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            copy_[i] = array[i];
        }
        return copy_;
    }

    function concat(
        address[] memory a,
        address[] memory b
    ) internal pure returns (address[] memory result) {
        result = new address[](a.length + b.length);
        for (uint256 i; i < a.length; i++) result[i] = a[i];
        for (uint256 i; i < b.length; i++) result[i + a.length] = b[i];
    }

    function includes(address[] memory array, address element) internal pure returns (bool) {
        return _includes(array, element, array.length);
    }

    function _includes(
        address[] memory array,
        address element,
        uint256 until
    ) internal pure returns (bool) {
        for (uint256 i; i < until; i++) {
            if (array[i] == element) return true;
        }
        return false;
    }

    function removeDuplicates(address[] memory array) internal pure returns (address[] memory) {
        address[] memory unique = new address[](array.length);
        uint256 j;
        for (uint256 i; i < array.length; i++) {
            if (!_includes(unique, array[i], j)) {
                unique[j++] = array[i];
            }
        }
        return trim(unique, j);
    }

    function trim(
        address[] memory array,
        uint256 length
    ) internal pure returns (address[] memory trimmed) {
        trimmed = new address[](length);
        for (uint256 i; i < length; i++) trimmed[i] = array[i];
    }
}
