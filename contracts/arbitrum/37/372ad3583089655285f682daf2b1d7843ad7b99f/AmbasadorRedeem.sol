
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Strings.sol";
import "./ECDSA.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";

contract AmbassadorRedeem is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    IERC20 public USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address private _signerAddress = 0x75ffe67F97D9259c08A8a3F192625752AEE66269;
    mapping(bytes32 => bool) public _swapKey;

    event RewardClaimed(address indexed _address, uint indexed _amount, string _data);
    
    constructor(){
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function SetUSDT(address _address) external onlyOwner{
        USDT = IERC20(_address);
    }

    function SetSigner(address _address) external onlyOwner{
        _signerAddress = _address;
    }

    function Claim(
        string calldata timestamp_,
        bytes calldata signature_,
        uint amount_
    ) external whenNotPaused {
        require(amount_ > 0, "Invalid amount");
        bytes32 message =  getMessage(timestamp_, amount_, address(this), msg.sender);
        require(!_swapKey[message], "Key Already Claimed");
        require(isValidData(message, signature_), "Invalid Signature");
        
        _swapKey[message] = true;
        USDT.safeTransfer(msg.sender, amount_);
        emit RewardClaimed(msg.sender, amount_, string.concat(string.concat(timestamp_, Strings.toString(amount_)), Strings.toHexString(uint256(uint160(msg.sender)), 20)));
    }

    function isValidData(
        bytes32 message_,
        bytes memory signature_
    ) public view returns (bool) {
        return message_
        .toEthSignedMessageHash()
        .recover(signature_) == _signerAddress;
    }

    function getMessage(
        string calldata timestamp_,
        uint amount_,
        address contractAddress_,
        address msgSender_
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(timestamp_, amount_, contractAddress_, msgSender_));
    }

    function save(address _token, uint _amount) external onlyOwner{
        IERC20(_token).transfer(msg.sender, _amount);
    }
}
