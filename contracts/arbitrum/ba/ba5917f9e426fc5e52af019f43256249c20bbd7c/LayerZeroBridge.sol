// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./IXERC20.sol";
import "./IXERC20Lockbox.sol";
import "./NonblockingLzApp.sol";

contract LayerZeroBridge is NonblockingLzApp {
    using SafeERC20 for IERC20;
    
    // Addresses needed
    IERC20 public BIFI;
    IXERC20 public xBIFI;
    IXERC20Lockbox public lockbox;

    uint16 private version = 1;
    uint256 public gasLimit;

    event BridgedOut(uint16 indexed dstChainId, address indexed bridgeUser, address indexed tokenReceiver, uint256 amount);
    event BridgedIn(uint16 indexed srcChainId, address indexed tokenReceiver, uint256 amount);

    constructor(
        IERC20 _bifi,
        IXERC20 _xbifi, 
        IXERC20Lockbox _lockbox,
        uint256 _gasLimit,
        address _endpoint
    ) NonblockingLzApp(_endpoint) {
        BIFI = _bifi;
        xBIFI = _xbifi;
        lockbox = _lockbox;
        gasLimit = _gasLimit;

        if (address(lockbox) != address(0)) {
            BIFI.safeApprove(address(lockbox), type(uint).max);
        }
        
    }

    function bridge(uint8 _dstChainId, uint256 _amount, address _to) external payable {
        
        // Lock BIFI in lockbox and burn minted tokens. 
        if (address(lockbox) != address(0)) {
            BIFI.safeTransferFrom(msg.sender, address(this), _amount);
            lockbox.deposit(_amount);
        }

        xBIFI.burn(address(this), _amount);

        // Send message to receiving bridge to mint tokens to user. 
        bytes memory adapterParams = abi.encodePacked(version, gasLimit);
        bytes memory payload = abi.encode(_to, _amount);
        
         _lzSend( // {value: messageFee} will be paid out of this contract!
                _dstChainId, // destination chainId
                payload, // abi.encode()'ed bytes
                payable(msg.sender), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
                address(0x0), // future param, unused for this example
                adapterParams, // v1 adapterParams, specify custom destination gas qty
                msg.value
        );

        emit BridgedOut(_dstChainId, msg.sender, _to, _amount);
    }

    function bridgeCost(uint16 _dstChainId, uint256 _amount, address _to) external view returns (uint256 gasCost) {
        bytes memory adapterParams = abi.encodePacked(version, gasLimit);
        bytes memory payload = abi.encode(_to, _amount);
        
        (gasCost,) = lzEndpoint.estimateFees(
            _dstChainId,
            address(this),
            payload,
            false,
            adapterParams
        );
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory /* _srcAddress */, 
        uint64, /*_nonce*/
        bytes memory _payload
    ) internal override {
        (address user, uint256 amount) = abi.decode(_payload, (address,uint256));

        xBIFI.mint(address(this), amount);
        if (address(lockbox) != address(0)) {
            lockbox.withdraw(amount);
            BIFI.transfer(user, amount);
        } else IERC20(address(xBIFI)).transfer(user, amount); 

        emit BridgedIn(_srcChainId, user, amount);      
    }

    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }
}
