// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20.sol";

import "./HopAMM.sol";
import "./IL2RevenueController.sol";
import "./IxTokenManager.sol";
import "./ILMTerminal.sol";

contract L2RevenueController is IL2RevenueController, Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // -- Constants --
    uint256 private constant ETH_CHAIN_ID = 1;

    // -- State Variables --
    address public hopBridge; // Hop exchange address used to bridge NATIVE TOKEN to L1
    address public oneInchRouterV4; // 1Inch V4 Rounter contract address
    address public nativeToken; // NATIVE TOKEN contract for the running network
    ILMTerminal public terminal; // LMTerminal contract
    IxTokenManager public xTokenManager; // xTokenManager contract
    address public l1RevenueController; // L1RevenueController contract address


    // -- Events --

    event FeeClaimed(address indexed fund, address indexed asset, uint256 amount);
    event AssetSwappedToNativeToken(address indexed fund, uint256 assetAmount, uint256 nativeTokenAmount);
    event SendToL1(uint256 amount);

    // -- Constructor / Initializer --

    function initialize(
        address _hopBridge,
        address _oneInchRouterV4,
        address _nativeToken,
        ILMTerminal _terminal,
        IxTokenManager _xTokenManager,
        address _l1RevenueController
    ) external initializer {
        __Ownable_init();

        hopBridge = _hopBridge;
        oneInchRouterV4 = _oneInchRouterV4;
        nativeToken = _nativeToken;
        terminal = _terminal;
        xTokenManager = _xTokenManager;
        l1RevenueController = _l1RevenueController;
    }

    // -- Management --

    /**
     * @dev Withdraws fees from the fund. The caller must the revenue controller owner or the xTokenManager contract
     * 
     * @param _token Address of the withdrawn token from terminal
     * @param _oneInchData Data needed for calling the 1Inch router for exchange (generated off-chain; exchange: _token --> nativeToken) 
     */
    function withdrawTerminalFees(address _token, bytes calldata _oneInchData) external override onlyOwnerOrManager {
        require(_token != address(0), "Invalid token address.");

        uint256 preActionBalance = address(this).balance;
        terminal.withdrawFees(_token);
        uint256 postActionBalance = address(this).balance;

        // Check native token balance for terminal withdrawal
        if (_token != nativeToken && postActionBalance != preActionBalance) {
            emit FeeClaimed(address(terminal), nativeToken, postActionBalance - preActionBalance);
        }

        uint256 tokenBalance = getTokenBalance(_token);

        if (tokenBalance == 0) {
            return;
        }

        emit FeeClaimed(address(terminal), _token, tokenBalance);

         if (_oneInchData.length < 32) {
            return;
        }

        swapTokenToNativeToken(_token, _oneInchData);
    }

    /**
     * @dev Function to send native token in contract to the L1 revenue controller
     *
     * @param nativeTokenAmount The amount of NATIVE TOKEN to send to L1 revenue controller
     * @param data The calldata to bridge NATIVE TOKEN through the Hop Bridge (generated off-chain)
     */
    function sendToL1(uint256 nativeTokenAmount, bytes calldata data) external override onlyOwnerOrManager {
        require(address(this).balance >= nativeTokenAmount, "Not enough native token amount in contract");
        // decode calldata
        (
            uint256 bonderFee, // fees passed to relayer
            uint256 amountOutMin,
            uint256 deadline
        ) = abi.decode(data, (uint256, uint256, uint256));

        // perform bridging
        HopAMM(hopBridge).swapAndSend{value: nativeTokenAmount}(
            ETH_CHAIN_ID,
            l1RevenueController,
            nativeTokenAmount,
            bonderFee,
            amountOutMin,
            deadline,
            amountOutMin,
            deadline
        );
        emit SendToL1(nativeTokenAmount);
    }

    /**
     * @dev Function to swap the specified token stored at the contract's address to NATIVE TOKEN
     *
     * @param _token Address of swapped token
     * @param _oneInchData Data needed for calling the 1Inch router for exchange (generated off-chain)
     */
    function swapToNativeToken(address _token, bytes calldata _oneInchData) public onlyOwnerOrManager {
        require(_token != address(0) && _token != nativeToken, "Invalid token address.");
        require(getTokenBalance(_token) > 0, "Contract token balance is zero.");
        require(_oneInchData.length >= 32, "Invalid 1Inch data.");

        swapTokenToNativeToken(_token, _oneInchData);
    }
    // -- Misc --

    function swapTokenToNativeToken(address _token, bytes memory _oneInchData) private {
        if (IERC20(_token).allowance(address(this), oneInchRouterV4) != type(uint256).max) {
            IERC20(_token).safeApprove(oneInchRouterV4, type(uint256).max);
        }

        (uint256 preActionAssetBalance, uint256 preActionNativeBalance) = snapshotAssetBalance(_token);
        (bool success, ) = oneInchRouterV4.call(_oneInchData);

        require(success, "1Inch swap failed.");

        (uint256 postActionAssetBalance, uint256 postActionNativeBalance) = snapshotAssetBalance(_token);
        emit AssetSwappedToNativeToken(
            _token,
            preActionAssetBalance - postActionAssetBalance,
            postActionNativeBalance - preActionNativeBalance
        );
    }

    function getTokenBalance(address _token) private view returns (uint256) {
        if (_token == nativeToken) return address(this).balance;
        return IERC20(_token).balanceOf(address(this));
    }

    function snapshotAssetBalance(address _asset) private view returns (uint256, uint256) {
        return (IERC20(_asset).balanceOf((address(this))), address(this).balance);
    }

    receive() external payable {
        require(msg.sender != tx.origin, "Errant native token deposit.");
    }

    // -- Modifiers --

    modifier onlyOwnerOrManager() {
        require(
            msg.sender == owner() || IxTokenManager(xTokenManager).isManager(msg.sender, address(this)),
            "Non-admin caller"
        );
        _;
    }
}

