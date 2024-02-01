// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;


import "./Initializable.sol";
import "./ReentrancyGuard.sol";


contract Buffer is Initializable, ReentrancyGuard {

    uint256 private totalReceived;
    uint256 public royaltyFeePercent;
    uint256 private montageShare;
    uint256 private montageFee;
    address public marketWallet; // wallet address for market fee
    address public owner;
    bytes32 private zeroNonce;

    
    error Unauthorized(address caller);
    error InvalidDataInput(uint256 expectedVal, uint256 realVal);
    error InvalidZN();

    event UpdateFeeCheck(uint256 feePercent);
    event WithdrawnCheck(address to, uint256 amount);
    event UpdateSharesCheck(uint256[] share);
    event FeeReceived(address to, uint256 amount);

    modifier onlyOwner() {
		_checkOwner();
		_;
    }

    modifier onlyGoodAddy() {

        require (tx.origin == msg.sender, "No external contract calls plz.");
        require (msg.sender != address(0));
        _;

        
    }


    function _checkOwner() internal view virtual {
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender);
        }
    }

    //============ Function to Receive ETH ============
    receive() external payable {
        totalReceived += msg.value;
        montageFee = msg.value * montageShare / 10000;
       
        _transfer(marketWallet, montageFee);
        montageFee  = 0;
        emit FeeReceived(address(this), msg.value);
    }

    //============ Function to Transfer Ownership ============
    function transferOwnership(address _newOwner) external onlyOwner onlyGoodAddy {
        owner = _newOwner;
    }

    //============ Function to Manually Jonce the Nonce ============
    function jonceTheNonce(bytes32 _joncyNoncy) external onlyOwner onlyGoodAddy {
        zeroNonce = _joncyNoncy;
    }

   
   
    
    //============ Function to Withdraw ETH ============
    function withdraw(string calldata _zeroNonce, uint256 _shareAmount, uint256 _wFee, bytes32 _newZeroNonce) external nonReentrant onlyGoodAddy {
        
        bytes32 hashZeroNonce = sha256(abi.encodePacked(_zeroNonce));

         if (hashZeroNonce != zeroNonce) {
            revert InvalidZN();
        }

       //amount to withdraw after fee
        uint256 _sendAmount = _shareAmount - _wFee;
        address account = msg.sender;

        _transfer(account, _sendAmount); 
       

    
       
        //payable(msg.sender).transfer(sendAmount);
       

    zeroNonce = _newZeroNonce;

    emit WithdrawnCheck(account, _sendAmount);
    }


    //============ Function to Initialize Contract ============
    function initialize(
        address _owner,
        address _marketWallet,
        uint256 _montageShare,
        bytes32 _zeroNonce
    
    ) public payable initializer {
        montageShare = _montageShare;
        marketWallet = _marketWallet;
        owner = _owner;
        royaltyFeePercent = 1000;
        zeroNonce = _zeroNonce;
        
    }
    //============ Function to Update Royalty Fee Percentage ============
    function updateFeePercent(uint256 _royaltyFeePercent) public onlyOwner onlyGoodAddy {
        if (_royaltyFeePercent > 10000) {
            revert InvalidDataInput(10000, _royaltyFeePercent);
        }
        royaltyFeePercent = _royaltyFeePercent;
        emit UpdateFeeCheck(royaltyFeePercent);
    }

    //============ Function to Check Total Recieved  ============
    function checkTotalRecieved() external view onlyOwner onlyGoodAddy returns (uint256)  {
        return totalReceived;
    }

    // adopted from https://github.com/lexDAO/Kali/blob/main/contracts/libraries/SafeTransferLib.sol
    error TransferFailed();
    //============ Function to Transfer ETH to Address ============
    function _transfer(address to, uint256 amount) internal {
        bool callStatus;
        assembly {
            callStatus := call(gas(), to, amount, 0, 0, 0, 0)
        }
        if (!callStatus) revert TransferFailed();
    }

    
}
