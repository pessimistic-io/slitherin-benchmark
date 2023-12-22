// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; 

import {IERC20} from "./ERC20.sol";
import {IERC20Permit} from "./ERC20Permit.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IXERC20} from "./IXERC20.sol";
import {IXERC20Lockbox} from "./IXERC20Lockbox.sol";
import {IAxelarGateway} from "./IAxelarGateway.sol";
import {IAxelarGasService} from "./IAxelarGasService.sol";
import {StringToAddress} from "./AddressString.sol";
import {AddressToString} from "./AddressString.sol";

// Axelar Token Bridge adapter for XERC20 tokens
contract AxelarBridge is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using StringToAddress for string;
    using AddressToString for address;
    
    // Addresses needed for bridging.
    IERC20 public BIFI;
    IXERC20 public xBIFI;
    IXERC20Lockbox public lockbox;
    IAxelarGateway public gateway;
    IAxelarGasService public gasService;

    // Gas limit for bridge calls.
    uint256 public gasLimit;

    // Chain id to axelar id mapping.
    mapping (uint256 => string) public chainIdToAxelarId;
    mapping (string => uint256) public axelarIdToChainId;

    // Errors
    error InvalidChainId();
    error NotGateway();
    error NotApprovedByGateway();
    error WrongSourceAddress();

    // Events
    event BridgedOut(uint256 indexed dstChainId, address indexed bridgeUser, address indexed tokenReceiver, uint256 amount);
    event BridgedIn(uint256 indexed srcChainId, address indexed tokenReceiver, uint256 amount);

    /**@notice Initialize the bridge
     * @param _bifi BIFI token address
     * @param _xbifi xBIFI token address
     * @param _lockbox xBIFI lockbox address
     * @param _gasLimit Gas limit for destination chain execution
     * @param _gateway Axelar gateway address
     * @param _gasService Axelar gas service address
     */
    function initialize(
        IERC20 _bifi,
        IXERC20 _xbifi, 
        IXERC20Lockbox _lockbox,
        uint256 _gasLimit,
        IAxelarGateway _gateway,
        IAxelarGasService _gasService
    ) public initializer {
        __Ownable_init();
        BIFI = _bifi;
        xBIFI = _xbifi;
        lockbox = _lockbox;
        gasLimit = _gasLimit;
        gateway = _gateway;
        gasService = _gasService;

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
        if (abi.encode(chainIdToAxelarId[_dstChainId]).length == 0) revert InvalidChainId();

        // Lock BIFI in lockbox and burn minted tokens. 
        if (address(lockbox) != address(0)) {
            BIFI.safeTransferFrom(_user, address(this), _amount);
            lockbox.deposit(_amount);
            xBIFI.burn(address(this), _amount);
        } else xBIFI.burn(_user, _amount);

        // Send message to receiving bridge to mint tokens to user. 
        bytes memory payload = abi.encode(_to, _amount);
 
        // Pay for our transaction on the other chain.
        gasService.payNativeGasForContractCall{value: msg.value}(
            address(this),
            chainIdToAxelarId[_dstChainId],
            address(this).toString(),
            payload,
            _user
        );

        // Send message to receiving bridge to mint tokens to user.
        gateway.callContract(
            chainIdToAxelarId[_dstChainId],
            address(this).toString(),
            payload
        );

        emit BridgedOut(_dstChainId, _user, _to, _amount);
    }

    // Estimate the gas cost of a bridge call. For axelar this needs to be call via api. 
    function bridgeCost(uint256, uint256, address) external pure returns (uint256 gasCost) {
        // Gas cost needs to be estimated via the axelar api. 
        return 0;
    }

    // Add a new chain id to the mapping. 
    function addChainIds(uint256[] calldata _chainIds, string[] calldata _axelarIds) external onlyOwner {
        for (uint i; i < _chainIds.length; ++i) {
            chainIdToAxelarId[_chainIds[i]] = _axelarIds[i];
            axelarIdToChainId[_axelarIds[i]] = _chainIds[i];
        }
    }

    // Execute a bridge in. Callable only by the gateway.
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        if (msg.sender != address(gateway)) revert NotGateway();
        if (axelarIdToChainId[sourceChain] == 0) revert InvalidChainId();
        if (sourceAddress.toAddress() != address(this)) revert WrongSourceAddress();
        
        bytes32 payloadHash = keccak256(payload);
        if (!gateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash)) revert NotApprovedByGateway();
       
        (address user, uint256 amount) = abi.decode(payload, (address,uint256));

        xBIFI.mint(address(this), amount);
        if (address(lockbox) != address(0)) {
            lockbox.withdraw(amount);
            BIFI.transfer(user, amount);
        } else IERC20(address(xBIFI)).transfer(user, amount); 

        emit BridgedIn(axelarIdToChainId[sourceChain], user, amount);      
    }

    // Set the gas limit for the bridge calls.
    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }
}
