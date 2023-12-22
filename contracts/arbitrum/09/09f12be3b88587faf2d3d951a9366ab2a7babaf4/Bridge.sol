// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./OwnableUpgradeable.sol";
import "./SafeERC20.sol";

import "./SafePermit.sol";

contract Bridge is OwnableUpgradeable {

    using SafeERC20 for IERC20;
    mapping(address => bool) public relayAddress;
    mapping(address => bool) public tokens;
    mapping(bytes32 => bool) public srcTxid;
    event Deposit(address indexed user, address indexed token, uint256 indexed dstChainId,
		uint256 amount, uint256 gas, address receiveAddress);
    event Withdraw(address indexed user, address indexed token, uint256 indexed srcChainId, uint256 amount, address receiveAddress, bytes32 txid);
    

    function initialize() public initializer {
        __Ownable_init();
        relayAddress[msg.sender] = true;
    }

    modifier onlyRelay() {
        require(relayAddress[msg.sender] == true, "Only relayAddress can perform this action");
        _;
    }
    modifier onlyToken(address _token) {
        require(tokens[_token] == true, "Only token can perform this action");
        _;
    }

    receive() external payable {}

    function addRelay(address _admin) public onlyOwner {
        relayAddress[_admin] = true;
    }
    function addToken(address _token) public onlyOwner {
        tokens[_token] = true;
    }
    
    function deposit(address _token, uint256 _amount, uint256 _dstChainId, uint256 _dstGas, address _receiveAddress) public payable { 
        require(_amount > 0, "Amount should be greater than zero");
        address user = msg.sender;
        IERC20(_token).safeTransferFrom(user, address(this), _amount);
        emit Deposit(user, _token, _dstChainId, _amount, _dstGas, _receiveAddress);
    }
    
    function depositWithPermit(address _token, uint256 _amount, uint256 _dstChainId, uint256 _dstGas, address _receiveAddress, bytes memory signature) external payable {
        SafePermit.permit(_token, msg.sender, signature);
        deposit(_token, _amount, _dstChainId, _dstGas, _receiveAddress);
    }

    function withdraw(address user, address _token, uint256 _amount, uint256 _srcChainId, bytes32 _srcTxid, address _receiveAddress) external onlyRelay onlyToken(_token) {
        require(!srcTxid[_srcTxid], "Bridge has already done!");
        IERC20(_token).safeTransfer(_receiveAddress, _amount);
        srcTxid[_srcTxid] = true; 
        emit Withdraw(user, _token, _srcChainId, _amount, _receiveAddress, _srcTxid);
    }

    function withdrawAll(address _token, address _recipient) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        uint amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_recipient, amount);
    }
}

