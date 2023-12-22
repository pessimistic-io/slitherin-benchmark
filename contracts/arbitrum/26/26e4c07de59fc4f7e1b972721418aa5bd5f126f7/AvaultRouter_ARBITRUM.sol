// SPDX-License-Identifier: GLP-v3.0

pragma solidity ^0.8.4;

import "./GnosisSafeStorage.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IStargateRouter.sol";
import "./IStargateReceiver.sol";
import "./IGnosisSafe.sol";
import "./IGnosisSafeProxyFactory.sol";
import "./UserOperation.sol";
import "./IStargateEthVault.sol";
import "./IModule.sol";
import "./IAvaultRouter.sol";
import "./ISwapRouter.sol";
import "./BytesLib.sol";
import "./Ownable.sol";

contract AvaultRouter_ARBITRUM is GnosisSafeStorage, IStargateReceiver, IAvaultRouter, Ownable {
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    mapping (address=>address) public userSafe; // cache use's safe address
    mapping (uint=>bytes) public chainIdToSGReceiver; // destChainId => sgReceiver, constrain for safety

    // SAFEPROXY_CREATIONCODE: https://arbiscan.io/address/0xa6b71e26c5e0845f74c812102ca7114b6a896ab2#readContract#F1
    // bytes public constant SAFEPROXY_CREATIONCODE = 0x60806040523480156100105760....70726f7669646564;
    // keccak256(abi.encodePacked(SAFEPROXY_CREATIONCODE, abi.encode(SAFE_SINGLETON)))
    bytes32 private constant BYTECODE_HASH = 0xcaf2dc2f91b804b2fcf1ed3a965a1ff4404b840b80c124277b00a43b4634b2ce;
    address private constant SAFE_SINGLETON = 0x3E5c63644E683549055b9Be8653de26E0B4CD36E;
    address private constant SAFE_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    address private constant SAFE_CALLBACK = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    address private constant SGETH = 0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0;
    address private constant STARGATE_ROUTER = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
    ISwapRouter private constant UNISWAP_ROUTER = ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    uint private constant ETH_POOL_ID = 13;
    address private constant SENTINEL_MODULES = address(0x1);

    address private constant MODULE = 0x2136182B0859F6F21C217E5854947b8Cb9D33295;
    bytes private constant ENABLE_MODULE_ENCODED = hex"610b59250000000000000000000000002136182b0859f6f21c217e5854947b8cb9d33295"; //abi.encodeWithSelector(IGnosisSafe.enableModule.selector, MODULE)

    uint private constant ADDRESS_ENCODE_LENGTH = 32;
    uint private constant ADDR_SIZE = 20;

    uint public constant SALT_NONCE = 0;

    event EXEC_ERROR(address srcAddress, string reason);
    event EXEC_PANIC(address srcAddress, uint errorCode);
    event EXEC_REVERT(address srcAddress, bytes lowLevelData);
    event SET_SGRECEIVER(uint indexed _chainId, address _sgReceiver);
    event EnabledModule(address module);

    // this contract needs to accept ETH
    receive() external payable {}

    function crossAssetCallNative(
        uint dstChainId,                      // Stargate/LayerZero chainId
        address payable _refundAddress,                     // message refund address if overpaid
        uint amountIn,                    // exact amount of native token coming in on source
        uint _dstGasForCall,             // gas for destination Stargate Router (including sgReceive)
        bytes memory payload            // (address _srcAddress, UserOperation memory _uo) = abi.decode(_payload, (address, UserOperation));
    )external payable{
        require(amountIn > 0, "amountIn must be greater than 0");
        require(msg.value > amountIn, "stargate requires fee to pay crosschain message");
        require(block.chainid != dstChainId, "not crosschain");
        
        // wrap the ETH into SGETH
        IStargateEthVault(SGETH).deposit{value: amountIn}();
        IStargateEthVault(SGETH).approve(STARGATE_ROUTER, amountIn);

        // messageFee is the remainder of the msg.value after wrap
        uint256 messageFee = msg.value - amountIn;
        // compose a stargate swap() using the WETH that was just wrapped
        bytes memory _sgReceiver = chainIdToSGReceiver[dstChainId];
        IStargateRouter(STARGATE_ROUTER).swap{value: messageFee}(
            uint16(dstChainId),                        // destination Stargate chainId
            ETH_POOL_ID,                             // WETH Stargate poolId on source
            ETH_POOL_ID,                             // WETH Stargate poolId on destination
            _refundAddress,                     // message refund address if overpaid
            amountIn,                          // the amount in Local Decimals to swap()
            amountIn * 99 / 100,                       // the minimum amount swap()er would allow to get out (ie: slippage)
            IStargateRouter.lzTxObj(_dstGasForCall, 0, "0x"),
            _sgReceiver,         // destination address, the sgReceive() implementer
            payload                           // empty payload, since sending to EOA
        );
        
    }

    //-----------------------------------------------------------------------------------------------------------------------
    // bridge asset and calldata, DO NOT call this if you don't know its meaning.
    function crossAssetCall(
        bytes calldata _path,             //uniswap exactIn path
        uint dstChainId,                      // Stargate/LayerZero chainId
        uint srcPoolId,                       // stargate poolId, scrToken should be USDC or USDT...
        uint dstPoolId,                       // stargate destination poolId, destToken could be USDC, USDT, BUSD or other stablecoin.
        address payable _refundAddress,                     // message refund address if overpaid
        uint amountIn,                    // exact amount of native token coming in on source
        uint amountOutMinSg,                    // minimum amount of stargatePoolId token to get out on destination chain
        uint _dstGasForCall,             // gas for destination Stargate Router (including sgReceive)
        bytes memory payload        // (address _srcAddress, UserOperation memory _uo) = abi.decode(_payload, (address, UserOperation));
    ) external payable{
        require(msg.value > 0, "gas fee required");
        require(amountIn > 0, 'amountIn == 0');
        require(block.chainid != dstChainId, "not crosschain");

        address _srcBridgeToken;
        {
            // user approved token
            address _userToken = _path.toAddress(0);
            IERC20(_userToken).transferFrom(msg.sender, address(this), amountIn);
            
            //swap if need
            _srcBridgeToken = _path.toAddress(_path.length - ADDR_SIZE);
            if(_srcBridgeToken != _userToken){
                IERC20(_userToken).safeIncreaseAllowance(address(UNISWAP_ROUTER), amountIn);
                ISwapRouter.ExactInputParams memory _t = ISwapRouter.ExactInputParams(_path, address(this), block.number + 10, amountIn, amountIn * 95 / 100);
                UNISWAP_ROUTER.exactInput(_t);
            }   
        }

        uint _srcBridgeTokenAmount = IERC20(_srcBridgeToken).balanceOf(address(this));
        IERC20(_srcBridgeToken).approve(STARGATE_ROUTER, _srcBridgeTokenAmount);
        IStargateRouter.lzTxObj memory _lzTxObj = IStargateRouter.lzTxObj(_dstGasForCall, 0, "0x");
        bytes memory _sgReceiver = chainIdToSGReceiver[dstChainId];
        // Stargate's Router.swap() function sends the tokens to the destination chain.
        IStargateRouter(STARGATE_ROUTER).swap{value:msg.value}(
            uint16(dstChainId),                                     // the destination chain id
            srcPoolId,                                      // the source Stargate poolId
            dstPoolId,                                      // the destination Stargate poolId
            _refundAddress,                            // refund adddress. if msg.sender pays too much gas, return extra eth
            _srcBridgeTokenAmount,                                   // total tokens to send to destination chain
            amountOutMinSg,                                 // minimum
            _lzTxObj,       // 500,000 for the sgReceive()
            _sgReceiver,         // destination address, the sgReceive() implementer
            payload                                            // bytes payload
        );
    }

    //-----------------------------------------------------------------------------------------------------------------------
    // sgReceive() - the destination contract must implement this function to receive the tokens and payload
    function sgReceive(uint16 /*_chainId*/, bytes memory /*_sgBridgeAddress*/, uint /*_nonce*/, address _token, uint amountLD, bytes memory _payload) override external {
        require(msg.sender == STARGATE_ROUTER, "only stargate router can call sgReceive!");

        address _srcAddress;
        UserOperation memory _uo;
        if(_payload.length <= ADDRESS_ENCODE_LENGTH){
            (_srcAddress) = abi.decode(_payload, (address));
        }else{
            (_srcAddress, _uo) = abi.decode(_payload, (address, UserOperation));
        }
        
        address _safe = userSafe[_srcAddress];
        if(_safe == address(0)){
            //calculate safe address
            bytes memory _initializer;
            (_safe, _initializer) = computeSafeAddress(_srcAddress);

            uint _size;
            assembly {
                _size := extcodesize(_safe)
            }
            if(_size == 0){
                //the _safe hasn't created, create it
                address _s = IGnosisSafeProxyFactory(SAFE_FACTORY).createProxyWithNonce(SAFE_SINGLETON, _initializer, SALT_NONCE);
                require(_safe == _s, "create safe error");
            }
            userSafe[_srcAddress] = _safe;
        }
        
        //transfer token to _safe
        if(_token == SGETH){
            (bool _success,) = _safe.call{value: amountLD}("");
            require(_success, "ETH transfer fail");
        }else{
            IERC20(_token).safeTransfer(_safe, amountLD);
        }

        if(_payload.length > ADDRESS_ENCODE_LENGTH){
            //try exec UO to _safe
            try IModule(MODULE).exec(_safe, _srcAddress, _uo){

            } catch Error(string memory reason) {
                // This is executed in case
                // revert was called inside execUO
                // and a reason string was provided.
                emit EXEC_ERROR(_srcAddress, reason);
            } catch Panic(uint errorCode) {
                // This is executed in case of a panic,
                // i.e. a serious error like division by zero
                // or overflow. The error code can be used
                // to determine the kind of error.
                emit EXEC_PANIC(_srcAddress, errorCode);
            } catch (bytes memory lowLevelData) {
                // This is executed in case revert() was used.
                emit EXEC_REVERT(_srcAddress, lowLevelData);
            }
        }
    }

    function computeSafeAddress(address _srcAddress) public view returns (address _safeAddr, bytes memory _initializer){
        address[] memory _owners = new address[](1);
        _owners[0] = _srcAddress;
        _initializer = abi.encodeWithSelector(IGnosisSafe.setup.selector, _owners, uint256(1), address(this), ENABLE_MODULE_ENCODED, SAFE_CALLBACK, address(0), 0, address(0));
        bytes32 _salt = keccak256(abi.encodePacked(keccak256(_initializer), SALT_NONCE));
        _safeAddr = computeAddress(_salt, BYTECODE_HASH, SAFE_FACTORY);
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy} from a contract located at
     * `deployer`. If `deployer` is this contract's address, returns the same value as {computeAddress}.
     */
    function computeAddress(
        bytes32 salt,
        bytes32 bytecodeHash,
        address deployer
    ) public pure returns (address addr) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40) // Get free memory pointer

            // |                   | ↓ ptr ...  ↓ ptr + 0x0B (start) ...  ↓ ptr + 0x20 ...  ↓ ptr + 0x40 ...   |
            // |-------------------|---------------------------------------------------------------------------|
            // | bytecodeHash      |                                                        CCCCCCCCCCCCC...CC |
            // | salt              |                                      BBBBBBBBBBBBB...BB                   |
            // | deployer          | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
            // | 0xFF              |            FF                                                             |
            // |-------------------|---------------------------------------------------------------------------|
            // | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
            // | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |

            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer) // Right-aligned with 12 preceding garbage bytes
            let start := add(ptr, 0x0b) // The hashed data starts at the final garbage byte which we will set to 0xff
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }

    function setSGReceiver(uint _chainId, address _sgReceiver) external onlyOwner{
        chainIdToSGReceiver[_chainId] = abi.encodePacked(_sgReceiver);
        emit SET_SGRECEIVER(_chainId, _sgReceiver);
    }

    /// @dev Allows to add a module to the safe's whitelist.
    ///      This can only be done via the Safe's delegatecall
    /// @notice Enables the module `module` for the Safe.
    /// @param module Module to be whitelisted.
    function enableModule(address module) external {
        // Module address cannot be null or sentinel.
        require(module != address(0) && module != SENTINEL_MODULES, "AGS101");
        modules[module] = modules[SENTINEL_MODULES];
        modules[SENTINEL_MODULES] = module;
        emit EnabledModule(module);
    }
}
