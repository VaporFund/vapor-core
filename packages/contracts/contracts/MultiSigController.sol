//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IMultiSigController.sol";


/*
 * @title MultiSigController
 * @dev a controller facilitating multi-signature operations within the system
 */



contract MultiSigController is ReentrancyGuard, IMultiSigController {
    using Address for address;

    struct Request {
        address contractAddress;
        bytes data; 
        bool executed;
        uint numConfirmations;
    }

    Request[] public requests;

    address[] private operators;
    mapping(address => bool) public isOperator;

    // Contract list
    mapping(address => bool) private contracts;

    uint8 public numConfirmationsRequired;

    address private admin; // this guy can only add and remove operators

    // mapping from request index => owner => bool
    mapping(uint32 => mapping(address => bool)) public isConfirmed;
    
    event SubmitRequest(
        uint32 indexed requestId,
        address indexed contractAddress
    );

    event ConfirmRequest(
        uint32 indexed requestId,
        address indexed contractAddress,
        address indexed operator
    );

    event RevokeRequest(
        uint32 indexed requestId,
        address indexed contractAddress,
        address indexed operator
    );

    event ExecuteRequest(
        uint32 indexed requestId,
        address indexed contractAddress,
        address indexed sender
    );

    constructor(address[] memory _operators, uint8 _numConfirmationsRequired) {
        require(_operators.length > 0, "operators required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _operators.length,
            "invalid number of required confirmations"
        );

        for (uint8 i = 0; i < _operators.length; i++) {
            address operator = _operators[i];

            require(operator != address(0), "invalid operator");
            require(!isOperator[operator], "operator not unique");

            isOperator[operator] = true;
            operators.push(operator);
        }

        numConfirmationsRequired = _numConfirmationsRequired;

        admin = msg.sender;
    }

    /// @notice transfer admin permission to the target address
    function transferAdmin(address _toAddress) external {
        require(msg.sender == admin, "unauthorized");
        admin = _toAddress;
    }

    /// @notice add operator
    function addOperator(address _operator) external {
        require(msg.sender == admin, "unauthorized");
        for (uint8 i = 0; i < operators.length; i++) {
            require(_operator != address(0), "invalid address");
            require(!isOperator[_operator], "duplicated");
        }
        isOperator[_operator] = true;
        operators.push(_operator);
    }

    /// @notice remove operator
    function removeOperator(address _operator) external {
        require(msg.sender == admin, "unauthorized");
        require(isOperator[_operator], "invalid address");
        uint index = 0;
        for (uint8 i = 0; i < operators.length; i++) {
            if (operators[i] == _operator) {
                index = i;
            }
        }
        // leave a gap to save gas
        delete operators[index];
        isOperator[_operator] = false;
    }

    /// @notice add supported contract that allows submission of requests
    function addContract(address _contractAddress) external onlyOperator {
        require(_contractAddress != address(0), "invalid address");
        require(!contracts[_contractAddress], "duplicated address");
        contracts[_contractAddress] = true;
    }

    /// @notice remove supported contract
    function removeContract(address _contractAddress) external onlyOperator {
        require(contracts[_contractAddress], "invalid address");
        contracts[_contractAddress] = false;
    }

    /// @notice submit a request
    function submitRequest(bytes memory _data) external onlyContract returns (uint32) {
        uint32 requestId = uint32(requests.length);

        requests.push(
            Request({
                contractAddress: msg.sender,
                data: _data,
                executed: false,
                numConfirmations: 0
            })
        );

        emit SubmitRequest(requestId, msg.sender);

        return requestId;
    }

    /// @notice operators confirm the pending request
    function confirmRequest(uint32 _requestId) 
        external 
        onlyOperator 
        requestExists(_requestId)
        notExecuted(_requestId)
        notConfirmed(_requestId)
    {
        Request storage request = requests[_requestId];
        unchecked {
            request.numConfirmations += 1;
        }
        
        isConfirmed[_requestId][msg.sender] = true;

        emit ConfirmRequest(_requestId, request.contractAddress, msg.sender);
    }

    /// @notice execute request's calldata against contract when the request reaches its threshold
    function executeRequest(uint32 _requestId)
        external 
        onlyOperator 
        requestExists(_requestId) 
        notExecuted(_requestId) 
    {
        Request storage request = requests[_requestId];

        require(
            request.numConfirmations >= numConfirmationsRequired,
            "threshold is not met"
        );

        request.executed = true;

        // TODO: support tx's value
        (bool success, ) = request.contractAddress.call(
            request.data
        );
        require(success, "tx failed");

        emit ExecuteRequest(_requestId, request.contractAddress, msg.sender);
    }

    /// @notice revoke a pending request from the caller 
    function revokeRequest(uint32 _requestId) external onlyOperator {
        Request storage request = requests[_requestId];

        require(isConfirmed[_requestId][msg.sender], "request not confirmed");

        request.numConfirmations -= 1;
        isConfirmed[_requestId][msg.sender] = false;

        emit RevokeRequest(_requestId, request.contractAddress, msg.sender);
    }   

    function getOperators() public view returns (address[] memory) {
        return operators;
    }
    
    function getRequest(uint _requestId)
        public
        view
        returns (
            address contractAddress, 
            bool executed,
            uint numConfirmations
        )
    {
        Request storage request = requests[_requestId];

        return (
            request.contractAddress,
            request.executed,
            request.numConfirmations
        );
    }

    function getRequestCount() public view returns (uint) {
        return requests.length;
    }

    /****************************************
     *          INTERNAL FUNCTIONS          *
     ****************************************/

    modifier onlyOperator() {
        require(isOperator[msg.sender], "only operator");
        _;
    }

    modifier onlyContract() {
        require(contracts[msg.sender], "unauthorized caller");
        _;
    }

    modifier requestExists(uint32 _requestIndex) {
        require(_requestIndex < requests.length, "ID does not exist");
        _;
    }

    modifier notExecuted(uint32 _requestIndex) {
        require(!requests[_requestIndex].executed, "ID already executed");
        _;
    }

    modifier notConfirmed(uint32 _requestIndex) {
        require(!isConfirmed[_requestIndex][msg.sender], "ID already confirmed");
        _;
    }

}
