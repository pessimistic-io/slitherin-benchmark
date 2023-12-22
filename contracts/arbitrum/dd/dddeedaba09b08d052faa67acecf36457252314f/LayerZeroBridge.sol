// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; 

import {IERC20} from "./ERC20.sol";
import {IERC20Permit} from "./ERC20Permit.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IXERC20} from "./IXERC20.sol";
import {IXERC20Lockbox} from "./IXERC20Lockbox.sol";
import  {NonblockingLzApp} from "./NonblockingLzApp.sol";

// Lazyer Zero Token Bridge adapter for XERC20 tokens
contract LayerZeroBridge is NonblockingLzApp {
    using SafeERC20 for IERC20;
    
    // Addresses needed
    IERC20 public BIFI;
    IXERC20 public xBIFI;
    IXERC20Lockbox public lockbox;

    // Bridge params
    uint16 private version = 1;
    uint256 public gasLimit;

    // Chain id mappings
    mapping (uint256 => uint16) public chainIdToLzId;
    mapping (uint16 => uint256) public lzIdToChainId;

    // Events
    event BridgedOut(uint256 indexed dstChainId, address indexed bridgeUser, address indexed tokenReceiver, uint256 amount);
    event BridgedIn(uint256 indexed srcChainId, address indexed tokenReceiver, uint256 amount);

    /**@notice Initialize the bridge
     * @param _bifi BIFI token address
     * @param _xbifi xBIFI token address
     * @param _lockbox xBIFI lockbox address
     * @param _gasLimit Gas limit for destination chain execution
     * @param _endpoint LayerZero endpoint address
     */
    function initialize(
        IERC20 _bifi,
        IXERC20 _xbifi, 
        IXERC20Lockbox _lockbox,
        uint256 _gasLimit,
        address _endpoint
    ) public initializer {
        __NonblockingLzAppInit(_endpoint);
        BIFI = _bifi;
        xBIFI = _xbifi;
        lockbox = _lockbox;
        gasLimit = _gasLimit;

        if (address(lockbox) != address(0)) {
            BIFI.safeApprove(address(lockbox), type(uint).max);
        }
        
    }

    /**@notice  Bridge out funds with permit
     * @param _user User address
     * @param _dstChainId Destination chain id 
     * @param _amount Amount of BIFI to bridge out
     * @param _to Address to receive funds on destination chain
     * @param _deadline Deadline for permit
     * @param v v value for permit
     * @param r r value for permit
     * @param s s value for permit
     */
    function bridge(address _user, uint256 _dstChainId, uint256 _amount, address _to, uint256 _deadline, uint8 v, bytes32 r, bytes32 s) external payable {
        IERC20Permit(address(BIFI)).permit(_user, address(this), _amount, _deadline, v, r, s);
        _bridge(_user, _dstChainId, _amount, _to);
    }

    /**@notice Bridge Out Funds
     * @param _dstChainId Destination chain id 
     * @param _amount Amount of BIFI to bridge out
     * @param _to Address to receive funds on destination chain
     */
    function bridge(uint256 _dstChainId, uint256 _amount, address _to) external payable {
        _bridge(msg.sender, _dstChainId, _amount, _to);
    }

    function _bridge(address _user, uint256 _dstChainId, uint256 _amount, address _to) private {
        // Lock BIFI in lockbox and burn minted tokens. 
        if (address(lockbox) != address(0)) {
            BIFI.safeTransferFrom(_user, address(this), _amount);
            lockbox.deposit(_amount);
            xBIFI.burn(address(this), _amount);
        } else xBIFI.burn(_user, _amount);

        // Send message to receiving bridge to mint tokens to user. 
        bytes memory adapterParams = abi.encodePacked(version, gasLimit);
        bytes memory payload = abi.encode(_to, _amount);
        
         _lzSend( // {value: messageFee} will be paid out of this contract!
                chainIdToLzId[_dstChainId], // destination chainId
                payload, // abi.encode()'ed bytes
                payable(_user), // refund address (LayerZero will refund any extra gas back to caller of send()
                address(0x0), // future param, unused for this example
                adapterParams, // v1 adapterParams, specify custom destination gas qty
                msg.value
        );

        emit BridgedOut(_dstChainId, _user, _to, _amount);
    }

    /**@notice Estimate gas cost to bridge out funds
     * @param _dstChainId Destination chain id 
     * @param _amount Amount of BIFI to bridge out
     * @param _to Address to receive funds on destination chain
     */
    function bridgeCost(uint256 _dstChainId, uint256 _amount, address _to) external view returns (uint256 gasCost) {
        bytes memory adapterParams = abi.encodePacked(version, gasLimit);
        bytes memory payload = abi.encode(_to, _amount);
        
        (gasCost,) = lzEndpoint.estimateFees(
            chainIdToLzId[_dstChainId],
            address(this),
            payload,
            false,
            adapterParams
        );
    }

    /**@notice Add chain ids to the bridge
     * @param _chainIds Chain ids to add
     * @param _lzIds LayerZero ids to add
     */
    function addChainIds(uint256[] calldata _chainIds, uint16[] calldata _lzIds) external onlyOwner {
        for (uint i; i < _chainIds.length; ++i) {
            chainIdToLzId[_chainIds[i]] = _lzIds[i];
            lzIdToChainId[_lzIds[i]] = _chainIds[i];
        }
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

        emit BridgedIn(lzIdToChainId[_srcChainId], user, amount);      
    }

    /**@notice Set gas limit for destination chain execution
     * @param _gasLimit Gas limit for destination chain execution
     */
    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }
}
