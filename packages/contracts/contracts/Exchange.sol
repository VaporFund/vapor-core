//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./WithdrawRequestNFT.sol";
import "./interfaces/IMultiSigController.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IWithdrawRequestNFT.sol";

import { Constants } from "./utility/Constants.sol";


/*
 * @title Exchange
 * @dev a simple exchange where VaporFund team is the sole seller, works by depositing ERC-20 tokens into the contract and creating an order specifying accepted tokens and amount. 
 * When settled, payment will be redirected to the main vault. Manual withdrawals can be made via the multi-signature controller only.
 */

 interface IWithdrawLiquidity {
    
    function withdrawLiquidity(address _token, uint256 _amount, address _recipient) external;

}

contract Exchange is ReentrancyGuard, IERC721Receiver, ERC721Holder {
    using Address for address;
    using SafeERC20 for IERC20;
    
    /// @dev controller for multi-sig operations
    IMultiSigController public controller;

    /// @dev main's vault on the chain
    IVault public vault;

    /// @dev NFT for requesting withdrawal
    IWithdrawRequestNFT public withdrawNft;
    
    struct Order {
        uint256 baseAmount; // must already be locked in the contract
        address[] pairTokens; // all tokens can be accepted as payment (not accept native tokens)
        uint256[] prices; // prices in different tokens and per unit in 10**18 ex. 1 BASE = 100 PAIR is 100*10**18
        address beneficialAddress;
        bool active;
        bool enabled;
    }

    struct WithdrawRequest {
        address fromToken;
        uint256 fromAmount;
        address toToken;
        uint256 toAmount;
        bool approved;
        bool completed;
    }

    /// @dev mapping of selling tokens to the corresponding details
    mapping(address => Order) public orders;

    /// @dev tracking withdrawal requests
    mapping(uint256 => WithdrawRequest) public requests;
    

    event OrderCreated(
        address indexed baseToken,
        uint256 baseAmount,
        address[] pairTokens,
        uint256[] prices,
        address beneficialAddress
    );

    event OrderUpdatedAmount(
        address indexed baseToken,
        uint256 updatedAmount
    );

    event OrderUpdatedPairs(
        address indexed baseToken,
        address[] pairTokens,
        uint256[] prices
    );

    event RequestWithdraw(
        uint256 indexed nftId,
        address fromToken,
        uint256 fromAmount,
        address toToken,
        uint256 toAmount,
        address indexed sender
    );

    event Withdrawn(
        uint256 indexed nftId,
        address indexed sender
    );

    event LiquidityWithdraw(
        address indexed tokenAddress,
        uint amount,
        uint balance
    );

    event Swapped(address indexed baseAddress, address fromAssetAddress, uint256 inputAmount, uint256 outputAmount);

    constructor(address _controller, address _vault) {
        controller = IMultiSigController(_controller);
        vault = IVault(_vault);

        WithdrawRequestNFT nftAddress = new WithdrawRequestNFT(address(this));
        withdrawNft = IWithdrawRequestNFT(address(nftAddress));
    }

    /// @notice buy base tokens with given pair tokens
    function buy(address _baseToken, uint256 _outputAmount, address _fromAsset, uint256 _maxInputAmount) external nonReentrant {
        require( orders[_baseToken].active == true ,"invalid token" );
        require( orders[_baseToken].enabled == true ,"order disabled" );
        require( orders[_baseToken].baseAmount >=  _outputAmount && IERC20(_baseToken).balanceOf(address(this)) >=  _outputAmount, "out of supply");
        require( type(uint128).max > _outputAmount && type(uint128).max > _maxInputAmount,"amount overflowed");

        for (uint8 i = 0; i < orders[_baseToken].pairTokens.length; i++) {
            address pairToken = orders[_baseToken].pairTokens[i];
            if (pairToken == _fromAsset) {
                uint256 pricePerUnit = orders[_baseToken].prices[i];
                uint256 requireInputAmount = (pricePerUnit*_outputAmount)/(10**18);
                require( _maxInputAmount >= requireInputAmount , "exceeds _maxInputAmount");
                
                orders[_baseToken].baseAmount -= _outputAmount;

                // taking payment
                IERC20(_fromAsset).safeTransferFrom(msg.sender, orders[_baseToken].beneficialAddress, requireInputAmount);

                // sending base tokens
                IERC20(_baseToken).transfer(msg.sender, _outputAmount);
                
                emit Swapped(_baseToken, _fromAsset, requireInputAmount, _outputAmount);

                break;
            }

        }

    }

    /// @notice request a withdrawal and issue an NFT
    function requestWithdraw(address _fromToken, uint256 _fromAmount, address _toToken, uint256 _toAmount) external nonReentrant {
        require( orders[_fromToken].active == true ,"invalid token" );
        require( IERC20(_fromToken).balanceOf( msg.sender ) >= _fromAmount, "insufficient balance");

        uint256 tokenId = withdrawNft.mint(_fromToken, _fromAmount, msg.sender);
    
        requests[tokenId].fromToken = _fromToken;
        requests[tokenId].fromAmount = _fromAmount;
        requests[tokenId].toToken = _toToken;
        requests[tokenId].toAmount = _toAmount;
        requests[tokenId].approved = false;
        requests[tokenId].completed = false;

        emit RequestWithdraw(tokenId, _fromToken, _fromAmount, _toToken, _toAmount, msg.sender);
    }

    /// @notice withdraw by burning the approved NFT and corresponding tokens
    function withdraw(uint256 _requestId) external nonReentrant {
        require( requests[_requestId].approved , "request is not approved" );
        require( !requests[_requestId].completed , "already withdrawn" );
        require( IERC20(requests[_requestId].fromToken).balanceOf( msg.sender ) >= requests[_requestId].fromAmount, "insufficient balance");
        require( IERC20(requests[_requestId].toToken).balanceOf( address(this)) >= requests[_requestId].toAmount, "insufficient liquidity");

        // taking NFT 
        IERC721(address(withdrawNft)).safeTransferFrom(
            msg.sender,
            address(this),
            _requestId
        );

        // transfering tokens to the vault
        IERC20(requests[_requestId].fromToken).safeTransferFrom(msg.sender, address(vault), requests[_requestId].fromAmount);
        
        // sending back payment
        IERC20(requests[_requestId].toToken).transfer(msg.sender, requests[_requestId].toAmount);

        requests[_requestId].completed = true;

        emit Withdrawn(_requestId, msg.sender); 
    }

    /****************************************
     *          OPERATOR FUNCTIONS          *
     ****************************************/

    /// @notice create an order for the given token
    function setupNewOrder(address _tokenAddress, uint256 _amount, address[] memory _pairTokens, uint256[] memory _prices) external onlyOperator  {
        require( orders[_tokenAddress].active == false ,"token is already listed" );
        require( _amount > 0, "invalid amount");
        require( IERC20(_tokenAddress).balanceOf( address(this) ) >= _amount, "insufficient balance");
        require( _pairTokens.length > 0 && _pairTokens.length == _prices.length , "invalid array length");

        orders[_tokenAddress].active = true;
        orders[_tokenAddress].enabled = true;
        orders[_tokenAddress].beneficialAddress = address(vault);
        orders[_tokenAddress].prices = _prices;
        orders[_tokenAddress].pairTokens = _pairTokens;
        orders[_tokenAddress].baseAmount = _amount;

        emit OrderCreated(_tokenAddress, _amount, _pairTokens, _prices, address(vault));
    }

    /// @notice disable an order
    function disableOrder(address _baseToken) external onlyOperator {
        require( orders[_baseToken].active == true ,"invalid order" );
        orders[_baseToken].enabled = false;
    }

    /// @notice enable an order
    function enableOrder(address _baseToken) external onlyOperator {
        require( orders[_baseToken].active == true ,"invalid order" );
        orders[_baseToken].enabled = true;
    }

    /// @notice update order amount
    function updateOrderAmount(address _baseToken, uint256 _amount) external onlyOperator {
        require( orders[_baseToken].active == true ,"invalid order" );
        require( _amount > 0, "invalid amount");
        require( IERC20(_baseToken).balanceOf( address(this) ) >= _amount, "insufficient balance" );

        orders[_baseToken].baseAmount = _amount;

        emit OrderUpdatedAmount(_baseToken, _amount);
    }

    /// @notice update order prices
    function updateOrderPrices(address _baseToken, address[] memory _pairTokens, uint256[] memory _prices) external onlyOperator {
        require( orders[_baseToken].active == true ,"invalid order" );
        require( _pairTokens.length > 0 && _pairTokens.length == _prices.length , "invalid array length" );
    
        orders[_baseToken].pairTokens = _pairTokens;
        orders[_baseToken].prices = _prices;

        emit OrderUpdatedPairs(_baseToken, _pairTokens, _prices);
    }

    /// @notice approve withdrawal requests
    function approveRequestWithdraw(uint8[] memory tokenIds) external onlyOperator {
        for (uint8 i = 0; i < tokenIds.length; i++) {
            requests[tokenIds[i]].approved = true;
        }
    }

    /// @notice add liquidity for withdrawal, alternatively, tokens can be transferred directly to the contract
    function addLiquidityForWithdrawal(address _token, uint256 _amount) external onlyOperator  {
        require( _amount > 0, "invalid amount");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice submit a liquidity withdrawal request 
    // function requestLiquidityWithdraw(address _token, uint256 _amount, address _recipient) external onlyOperator {
    //     require( _amount > 0, "invalid amount");

    //     if (_token == Constants.ETH_TOKEN) {
    //         require(address(this).balance >= _amount, "insufficent liquidity");
    //     } else {
    //         require(
    //             IERC20(_token).balanceOf(address(this)) >= _amount,
    //             "insufficent liquidity"
    //         );
    //     }

    //     uint32 currentRequestId = controller.submitRequest(address(this) , abi.encodeCall(IWithdrawLiquidity.withdrawLiquidity, (_token, _amount, _recipient)));

    //     emit RequestLiquidityWithdraw(msg.sender, _token, _amount, _recipient, currentRequestId);
    // }

    /// @notice withdraw liquidity to the vault
    function withdrawLiquidity(address _token, uint256 _amount) external onlyOperator {
        if (_token == Constants.ETH_TOKEN) {
            (bool sent, ) = address(vault).call{value: _amount}("");
            require(sent, "sent ETH failed");
            emit LiquidityWithdraw(_token, _amount, address(this).balance);
        } else {
            IERC20(_token).safeTransfer(address(vault), _amount);
            emit LiquidityWithdraw(_token, _amount, IERC20(_token).balanceOf(address(this)));
        }
    }

    /****************************************
     *          INTERNAL FUNCTIONS          *
     ****************************************/

    modifier onlyOperator() {
        require(controller.isOperator(msg.sender), "only operator");
        _;
    }

}