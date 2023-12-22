// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./IWETH.sol";
import "./BaseContract.sol";
import "./IRangoHyphen.sol";
import "./IHyphenBridge.sol";

/// @title The root contract that handles Rango's interaction with hyphen
/// @author Hellboy
/// @dev This is deployed as a separate contract from RangoV1
contract RangoHyphen is IRangoHyphen, BaseContract {

    /// @notice The address of hyphen contract
    address hyphenAddress;

    /// @notice Emits when the hyphen address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event HyphenAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice The constructor of this contract that receives WETH address and initiates the settings
    /// @param _nativeWrappedAddress The address of WETH, WBNB, etc of the current network
    constructor(address _nativeWrappedAddress) {
        BaseContractStorage storage baseStorage = getBaseContractStorage();
        baseStorage.nativeWrappedAddress = _nativeWrappedAddress;
        hyphenAddress = NULL_ADDRESS;
    }

    /// @notice Updates the address of hyphen contract
    /// @param _address The new address of hyphen contract
    function updateHyphenAddress(address _address) external onlyOwner {
        address oldAddress = hyphenAddress;
        hyphenAddress = _address;
        emit HyphenAddressUpdated(oldAddress, _address);
    }

    /// @notice Emits when a native token bridge request is sent to hyphen bridge
    /// @param _receiver The receiver address in the destination chain
    /// @param _dstChainId The network id of destination chain, ex: 56 for BSC
    /// @param _amount The requested amount to bridge
    event HyphenNativeDeposit(uint256 _dstChainId, address _receiver, uint256 _amount);

    /// @notice Emits when an ERC20 token (non-native) bridge request is sent to hyphen bridge
    /// @param _dstChainId The network id of destination chain, ex: 56 for BSC
    /// @param _token The requested token to bridge
    /// @param _receiver The receiver address in the destination chain
    /// @param _amount The requested amount to bridge
    event HyphenERC20Deposit(uint256 _dstChainId, address _token, address _receiver, uint256 _amount);

    /// @inheritdoc IRangoHyphen
    function hyphenBridge(
        address _receiver,
        address _token,
        uint256 _amount,
        uint256 _dstChainId
    ) external override whenNotPaused nonReentrant {
        require(hyphenAddress != NULL_ADDRESS, 'Hyphen address not set');
        require(block.chainid != _dstChainId, 'Cannot bridge to the same network');
        SafeERC20.safeTransferFrom(IERC20(_token), msg.sender, address(this), _amount);
        if (_token == address(0)) {
            IHyphenBridge(hyphenAddress).depositNative{ value: _amount }(_receiver, _dstChainId, "Rango");
            emit HyphenNativeDeposit(_dstChainId, _receiver, _amount);
        } else{
            approve(_token, hyphenAddress, _amount);
            IHyphenBridge(hyphenAddress).depositErc20(_receiver, _dstChainId, _token, _amount, "Rango");
            emit HyphenERC20Deposit(_dstChainId, _token, _receiver, _amount);
        }
    }

}
