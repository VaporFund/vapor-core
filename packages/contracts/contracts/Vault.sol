//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IMultiSigController.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IElasticToken.sol";

import { Constants } from "./utility/Constants.sol";

/*
 * @title Vault
 * @dev a vault contract responsible for locking tokens for any purpose. also acts as the bridge interface between all supported chains.
 */

interface IWithdraw {
    function withdraw(address _token, uint256 _amount, address _recipient) external;

    function withdrawAndStake(address _token, uint256 _amount, string memory _stakingProtocol, address _stakingAddress, bytes memory _data) external;

    function unstake(address _token, uint256 _amount, string memory _stakingProtocol, address _stakingAddress, bytes memory _data) external;

    function fulfill(bytes32 _txHash) external;
}

interface ITokenFactory {

    function createToken(string calldata tokenName, string calldata tokenSymbol, uint8 tokenDecimals, address owner) external returns (IElasticToken newToken);
        
}

contract Vault is ReentrancyGuard, IVault {
    using Address for address;
    using SafeERC20 for IERC20;

    /// @dev the chain id of the contract, is passed in to avoid any evm issues
    uint256 public immutable chainId;    

    /// @dev all requests or any related to supply sync between chains require multi-signing from the controller
    IMultiSigController public controller;

    /// @dev mapping of hash of `TransactionData` to status of a transaction
    mapping(bytes32 => TransactionStatus) public transactionStatus;

    /// @dev mapping of hash of `TransactionData` to the data
    mapping(bytes32 => TransactionData) public transactionData;
    
    /// @dev all bridge tokens on the child chain side
    address[] public bridgeTokens;

    /// @dev to deploy a new token elastic contract
    ITokenFactory public factory;

    /// @dev track tokens out
    mapping(address => uint256) public totalValueOutOfChain;
    
    event Deposit(
        address indexed sender,
        address indexed tokenAddress,
        uint amount,
        uint balance
    );

    event RequestWithdraw(
        address indexed operator,
        address indexed tokenAddress,
        uint amount,
        address recipient,
        uint32 requestId
    );

    event Withdraw(
        address indexed tokenAddress,
        uint amount,
        uint balance
    );

    event WithdrawAndStake(
        address indexed tokenAddress,
        uint amount,
        uint balance,
        string stakingProtocol,
        address stakingAddress
    );

    event UnstakeAndDeposit(
        address indexed tokenAddress,
        uint amount,
        uint balance,
        string stakingProtocol,
        address stakingAddress
    );

    event TransactionPrepared(TransactionData txData, address indexed operator, uint32 requestId);

    event TransactionFulfilled(TransactionData txData, bytes32 txHash);

    constructor(uint256 _chainId, address _controller) {
        chainId = _chainId;
        controller = IMultiSigController(_controller);
    }

    /// @notice set token factory contract
    function setTokenFactory(address _factory) external onlyOperator {
        factory = ITokenFactory(_factory);
    }

    /// @notice deploy new bridge token contract
    function createToken(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint8 tokenDecimals
    ) external onlyOperator {
        require( address(factory) != address(0) , "token factory is not set");
        IElasticToken newToken = factory.createToken(tokenName, tokenSymbol, tokenDecimals, address(this));
        bridgeTokens.push(address(newToken));
    }

    /// @notice deposit native ETH
    receive() external payable {
        emit Deposit(
            msg.sender,
            Constants.ETH_TOKEN,
            msg.value,
            address(this).balance
        );
    }

    /// @notice another way to deposit native ETH
    function depositWithETH() payable external nonReentrant  {
        emit Deposit(
            msg.sender,
            Constants.ETH_TOKEN,
            msg.value,
            address(this).balance
        );
    }

    /// @notice deposit ERC-20 tokens
    function depositWithERC20(address _token, uint256 _amount) external nonReentrant {
        require(_token != Constants.ETH_TOKEN, "ETH should be called another func.");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(
            msg.sender,
            _token,
            _amount,
            IERC20(_token).balanceOf(address(this))
        );
    }

    /// @notice submit a withdrawal request
    function requestWithdraw(address _token, uint256 _amount, address _recipient) external onlyOperator {
        require( controller.isOperator(msg.sender), "unauthorized");

        if (_token == Constants.ETH_TOKEN) {
            require(address(this).balance >= _amount, "insufficent funds");
        } else {
            require(
                IERC20(_token).balanceOf(address(this)) >= _amount,
                "insufficent funds"
            );
        }

        uint32 currentRequestId = controller.submitRequest(address(this) , abi.encodeCall(IWithdraw.withdraw, (_token, _amount, _recipient)));

        emit RequestWithdraw(msg.sender, _token, _amount, _recipient, currentRequestId);
    }

    /// @notice perform withdrawal
    function withdraw(address _token, uint256 _amount, address _recipient) external onlyController {
        if (_token == Constants.ETH_TOKEN) {
            (bool sent, ) = _recipient.call{value: _amount}("");
            require(sent, "sent ETH failed");
            emit Withdraw(_token, _amount, address(this).balance);
        } else {
            IERC20(_token).safeTransfer(_recipient, _amount);
            emit Withdraw(_token, _amount, IERC20(_token).balanceOf(address(this)));
        }
    }

    /// @notice withdraw and then stake in the respective protocol
    function withdrawAndStake(address _token, uint256 _amount, string memory _stakingProtocol, address _stakingAddress, bytes memory _data) external onlyController {
        if (_token == Constants.ETH_TOKEN) {
            (bool success, ) = _stakingAddress.call{value: _amount}(
                _data
            );
            require(success, "stake failed in vault.sol");
        } else {
            
            (bool success, ) = _stakingAddress.call(
                _data
            );
            require(success, "stake failed in vault.sol");
        }

        emit WithdrawAndStake(_token, _amount, address(this).balance, _stakingProtocol, _stakingAddress);
    }

    /// @notice unstake from the give protocol (alternative option is withdraw and perform unstaking manually)
    function unstake(address _token, uint256 _amount, string memory _stakingProtocol, address _stakingAddress, bytes memory _data) external onlyController {

        (bool success, ) = _stakingAddress.call(
                _data
        );
        require(success, "unstake failed in vault.sol");

        if (_token == Constants.ETH_TOKEN) {
            emit UnstakeAndDeposit(_token, _amount, address(this).balance, _stakingProtocol, _stakingAddress);
        } else {
            emit UnstakeAndDeposit(_token, _amount, IERC20(_token).balanceOf(address(this)) , _stakingProtocol, _stakingAddress);
        }
    
    }

    /// @notice authorize interface contract to transfer tokens from vault
    function approve(address _token, address _stakingAddress) external onlyOperator {
        IERC20(_token).approve(_stakingAddress, type(uint256).max);
    }

    /****************************************
     *          CROSS-CHAIN FUNCTIONS       *
     ****************************************/

    /// the cross-chain part has forked from the early version of the Connext protocol aiming to be simple and minimize.
    /// https://github.com/connext/monorepo/archive/refs/tags/v0.0.49.zip
    
    /// @notice prepare pending transactions that need to be executed on both side.
    function prepare(InvariantTransactionData calldata _txData, uint256 amount) external onlyOperator {
        require(_txData.sendingChainId != _txData.receivingChainId, "same chain ID is not allowed");
        require(_txData.sendingChainId == chainId || _txData.receivingChainId == chainId, "invalid chain ID");

        TransactionData memory txData = TransactionData({
            sendingAssetId: _txData.sendingAssetId,
            receivingAssetId: _txData.receivingAssetId,
            callData: _txData.callData,
            amount: amount,
            blockNumber: block.number,
            sendingChainId: _txData.sendingChainId,
            receivingChainId: _txData.receivingChainId,
            transactionType: _txData.transactionType
        });

        bytes32 digest = keccak256(abi.encode(txData));
        require(transactionStatus[digest] == TransactionStatus.Empty, "digest exists");

        // Store the transaction variants
        transactionStatus[digest] = TransactionStatus.Pending;
        transactionData[digest] = txData;

        // determine if this is sender side or receiver side
        if (txData.sendingChainId == chainId && txData.transactionType == TransactionType.Mint) {
            if (_txData.sendingAssetId == Constants.ETH_TOKEN) {
                require(address(this).balance >= amount, "insufficent funds");
            } else {
                require(
                    IERC20(_txData.sendingAssetId).balanceOf(address(this)) >= amount,
                    "insufficent funds"
                );
            }
        }

        uint32 currentRequestId = controller.submitRequest(address(this) , abi.encodeCall(IWithdraw.fulfill, ( digest)));

        emit TransactionPrepared( txData, msg.sender, currentRequestId);
    }

    /// @notice approve the pending transactions, each side having a different flow as follows:
    /// parent chain (ETH) - lock assets in the vault when the transaction type is Mint, unlock assets when it is Burn.
    /// child chain (BNB, OP) - mint or burn bridged assets as per calldata
    function fulfill(bytes32 _txHash) external onlyController {
        require(transactionStatus[_txHash] == TransactionStatus.Pending, "invalid hash");

        // store tx data and retrive it
        transactionStatus[_txHash] == TransactionStatus.Completed;
        TransactionData memory txData = transactionData[_txHash];

        if (txData.sendingChainId == chainId) {
            // minting or rebasing
            if (txData.transactionType == TransactionType.Mint || txData.transactionType == TransactionType.Rebase) {
                unchecked {
                    totalValueOutOfChain[txData.sendingAssetId] += txData.amount;
                }
            }
            // burning
            if (txData.transactionType == TransactionType.Burn) {
                totalValueOutOfChain[txData.sendingAssetId] -= txData.amount;
            }
        }

        if (txData.receivingChainId == chainId) {
            // TODO: checking on the array
            (bool success, ) = txData.receivingAssetId.call(
                txData.callData
            );
            require(success, "fulfill failed");
        }

        emit TransactionFulfilled(txData, _txHash);
    }

    function getCalldataMint(address _recipient, uint256 _amount) external pure returns (bytes memory) {
        return abi.encodeCall(IElasticToken.mintTo, ( _recipient, _amount));
    }

    function getCalldataBurn(address _recipient, uint256 _amount) external pure returns (bytes memory) {
        return abi.encodeCall(IElasticToken.burn, ( _recipient, _amount ));
    }

    function getCalldataRebase(int128 _accruedRewards) external pure returns (bytes memory) {
        return abi.encodeCall(IElasticToken.rebase, ( _accruedRewards ));
    }

    /****************************************
     *          INTERNAL FUNCTIONS          *
     ****************************************/

    modifier onlyController() {
        require(msg.sender == address(controller), "only controller");
        _;
    }

    modifier onlyOperator() {
        require(controller.isOperator(msg.sender), "only operator");
        _;
    }

}