//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IMultiSigController.sol";
import "./interfaces/IVault.sol";


/*
 * @title Exchange
 * @dev a simple exchange where VaporFund team is the sole seller, works by depositing ERC-20 tokens into the contract and creating an order specifying accepted tokens and amount. 
 * When settled, payment will be redirected to the main vault. Manual withdrawals can be made via the multi-signature controller only.
 */

contract Exchange is ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;
    
    /// @dev controller for multi-sig operations
    IMultiSigController public controller;

    /// @dev main's vault on the chain
    IVault public vault;
    
    struct Order {
        uint256 baseAmount; // must already be locked in the contract
        address[] pairTokens; // all tokens can be accepted as payment (not accept native tokens)
        uint256[] prices; // prices in different tokens and per unit in 10**18 ex. 1 BASE = 100 PAIR is 100*10**18
        address beneficialAddress;
        bool active;
        bool enabled;
    }

    /// @dev mapping of selling tokens to the corresponding details
    mapping(address => Order) public orders;

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

    event Swapped(address indexed baseAddress, address fromAssetAddress, uint256 inputAmount, uint256 outputAmount);

    constructor(address _controller, address _vault) {
        controller = IMultiSigController(_controller);
        vault = IVault(_vault);
    }

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

    /// @notice buy base tokens with given pair tokens
    function buy(address _baseToken, uint256 _outputAmount, address _fromAsset, uint256 _maxInputAmount) external nonReentrant {
        require( orders[_baseToken].active == true ,"invalid order" );
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


    // TODO: request withdraw

    // TODO: withdraw

    // TODO: topup liquidity

    // TODO: withdraw liquidity

    modifier onlyOperator() {
        require(controller.isOperator(msg.sender), "only operator");
        _;
    }

}