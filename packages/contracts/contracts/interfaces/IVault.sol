// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVault {

    enum TransactionType {
        Mint,
        Rebase,
        Burn
    }

    struct InvariantTransactionData {
        address sendingAssetId;
        address receivingAssetId;
        uint256 sendingChainId;
        uint256 receivingChainId;
        bytes callData;
        TransactionType transactionType;
    }

    enum TransactionStatus {
        Empty,
        Pending,
        Completed
    }

    struct TransactionData {
        address sendingAssetId;
        address receivingAssetId;
        bytes callData;
        uint256 amount;
        uint256 blockNumber;
        uint256 sendingChainId;
        uint256 receivingChainId;
        TransactionType transactionType;
    }

}