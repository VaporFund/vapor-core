// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMultiSigController {

    function submitRequest(bytes memory _data) external returns (uint32);

}