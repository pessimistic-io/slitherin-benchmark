// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Owned} from "./Owned.sol";
import {VaultInterface} from "./VaultInterface.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {WETHInterface} from "./WETHInterface.sol";

/// @title L1SocketDepositHelper
/// @notice The L1 deposit helper for handling cross-chain yield vault deposits and usdc permit
contract L1SocketDepositHelper is Owned {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The arb / op vault contract
    mapping(address => VaultInterface) public vaults;

    /// @notice The WETH address
    address public immutable weth;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokensDeposited(
        address indexed connector,
        address indexed depositor,
        address indexed receiver,
        uint256 depositAmount,
        bytes data
    );
    event VaultUpdated(address indexed collateral, address indexed vault);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor
    /// @param _weth The WETH address
    constructor(address _weth, address _owner) Owned(_owner) {
        weth = _weth;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the Socket vault for a collateral
    /// @dev Only callable by the owner
    /// @param _collateral The collateral address
    /// @param _vault The Socket vault address
    function updateVault(address _collateral, address _vault) external onlyOwner {
        vaults[_collateral] = VaultInterface(_vault);

        emit VaultUpdated(_collateral, _vault);
    }

    /// @notice Deposit an amount of the ERC20 to the senders balance on L2
    /// @param _receiver Receiver on the L2
    /// @param _amount Amount of to deposit
    /// @param _msgGasLimit Gas limit required to complete the deposit on L2
    /// @param _connector Socket connector
    /// @param _data Optional data to forward to L2
    function depositETHToAppChain(
        address _receiver,
        uint256 _amount,
        uint256 _msgGasLimit,
        address _connector,
        bytes calldata _data
    ) external payable {
        // Mint WETH
        WETHInterface(weth).deposit{value: _amount}();
        // Approve the tokens from this contract to the L1 bridge
        ERC20(weth).safeApprove(address(vaults[weth]), _amount);
        vaults[weth].depositToAppChain{value: msg.value - _amount}(_receiver, _amount, _msgGasLimit, _connector);
        emit TokensDeposited(_connector, msg.sender, _receiver, _amount, _data);
    }

    /// @notice Deposit an amount of the ERC20 to the senders balance on L2 using an EIP-2612 permit signature
    /// @param _receiver Receiver on the L2
    /// @param _asset Asset of the ERC20
    /// @param _amount Amount of the ERC20 to deposit
    /// @param _msgGasLimit Gas limit required to complete the deposit on L2
    /// @param _connector Socket connector
    /// @param _data Optional data to forward to L2
    /// @param _deadline A timestamp, the current blocktime must be less than or equal to this timestamp
    /// @param _v Must produce valid secp256k1 signature from the holder along with r and s
    /// @param _r Must produce valid secp256k1 signature from the holder along with v and s
    /// @param _s Must produce valid secp256k1 signature from the holder along with r and v
    function depositToAppChainWithPermit(
        address _receiver,
        address _asset,
        uint256 _amount,
        uint256 _msgGasLimit,
        address _connector,
        bytes calldata _data,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable {
        // Approve the tokens from the sender to this contract
        ERC20(_asset).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s);
        _depositToAppChain(_receiver, _asset, _amount, _msgGasLimit, _connector, _data);
    }

    /// @notice Deposit an amount of the ERC20 to the senders balance on L2
    /// @param _receiver Receiver on the L2
    /// @param _asset Asset of the ERC20
    /// @param _amount Amount of the ERC20 to deposit
    /// @param _msgGasLimit Gas limit required to complete the deposit on L2
    /// @param _connector Socket connector
    /// @param _data Optional data to forward to L2
    function depositToAppChain(
        address _receiver,
        address _asset,
        uint256 _amount,
        uint256 _msgGasLimit,
        address _connector,
        bytes calldata _data
    ) external payable {
        _depositToAppChain(_receiver, _asset, _amount, _msgGasLimit, _connector, _data);
    }

    function _depositToAppChain(
        address _receiver,
        address _asset,
        uint256 _amount,
        uint256 _msgGasLimit,
        address _connector,
        bytes calldata _data
    ) internal {
        // Transfer the tokens from the sender to this contract
        ERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        // Approve the tokens from this contract to the L1 bridge
        ERC20(_asset).safeApprove(address(vaults[_asset]), _amount);

        vaults[_asset].depositToAppChain{value: msg.value}(_receiver, _amount, _msgGasLimit, _connector);
        emit TokensDeposited(_connector, msg.sender, _receiver, _amount, _data);
    }
}

