//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./utility/ElasticToken.sol";
import "./interfaces/IElasticToken.sol";

/*
 * @title TokenFactory
 * @dev create a new token contract and grant permission to vault.sol.
 */

contract TokenFactory {
    
    event TokenCreated(address indexed tokenAddress);

    /**
     * @notice Create a new token and return it to the caller.
    */
    function createToken(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        address owner
    ) external returns (IElasticToken newToken) {
        ElasticToken mintableToken = new ElasticToken(tokenName, tokenSymbol, tokenDecimals, owner);
        newToken = IElasticToken(address(mintableToken));

        emit TokenCreated(address(newToken));
    }

}