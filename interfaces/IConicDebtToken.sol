// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/MerkleProof.sol";

interface IConicDebtToken is IERC20 {
    event DebtPoolSet(address indexed debtPool);
    event RefundClaimed(address claimant, uint256 amount);
    event ClaimingStarted();
    event DebtTokenClaimed(address claimant, uint256 amount);

    function depositRefund(uint256 amount) external;

    function start() external;

    function claimDebtToken(uint256 amount, MerkleProof.Proof calldata proof) external;

    function claimRefund(uint256 amount, MerkleProof.Proof calldata proof) external;

    function claimAll(
        uint256 amountDebtToken,
        MerkleProof.Proof calldata proofDebtTokenClaim,
        uint256 amountRefund,
        MerkleProof.Proof calldata proofRefund
    ) external;

    function setDebtPool(address debtPool) external;

    function burn(address account, uint256 amount) external;
}
