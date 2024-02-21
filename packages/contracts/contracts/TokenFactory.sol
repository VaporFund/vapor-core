//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

/*
 * @title TokenFactory
 * @dev 
 */

contract TokenFactory {
    
    event TokenCreated(address indexed tokenAddress);

    /**
     * @notice Create a new token and return it to the caller.
     * @dev The caller will become the only minter and burner and the new owner capable of assigning the roles.
     */
    // function createToken(
    //     string calldata tokenName,
    //     string calldata tokenSymbol,
    //     uint8 tokenDecimals
    // ) external nonReentrant() returns (IExpandedIERC20 newToken) {
    //     SyntheticToken mintableToken = new SyntheticToken(tokenName, tokenSymbol, tokenDecimals);
    //     mintableToken.addMinter(msg.sender);
    //     mintableToken.addBurner(msg.sender);
    //     mintableToken.resetOwner(msg.sender);
    //     newToken = IExpandedIERC20(address(mintableToken));

    //     emit TokenCreated(address(newToken));

    // }


}