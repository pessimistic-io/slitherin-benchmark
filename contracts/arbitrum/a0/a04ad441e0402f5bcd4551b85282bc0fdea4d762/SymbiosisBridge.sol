// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.6;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AddressUpgradeable.sol";

contract SymbiosisBridge is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using AddressUpgradeable for address payable;

    address public metaRouter;
    address public metaRouterGateway;
    address public feeAddress;
    uint32 public feeRate;

    address public owner;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        address _owner,
        address _metaRouter,
        address _metaRouterGateway,
        address _feeAddress,
        uint32 _feeRate
    ) public initializer {
        owner = _owner;
        metaRouter = _metaRouter;
        metaRouterGateway = _metaRouterGateway;
        feeAddress = _feeAddress;
        feeRate = _feeRate;
    }

    event SwapToken(
        address indexed fromAddress,
        address indexed fromToken,
        uint256 tokenAmount,
        address indexed txOrigin
    );

    event SwapEth(
        address indexed fromAddress,
        uint256 amount,
        address indexed txOrigin
    );

    function setOwner(address _owner) external {
        require(owner == address(0), "SymbiosisBridge: The Owner already set");

        owner = _owner;
    }

    function swapToken(
        IERC20Upgradeable fromToken,
        uint256 tokenAmount,
        bytes calldata data
    ) external {
        fromToken.transferFrom(msg.sender, address(this), tokenAmount);

        (uint256 feeAmount, uint256 swapAmount) = calculateAmounts(tokenAmount);

        fromToken.transfer(feeAddress, feeAmount);
        fromToken.approve(metaRouterGateway, swapAmount);

        metaRouter.functionCall(data);

        emit SwapToken(msg.sender, address(fromToken), tokenAmount, tx.origin);
    }

    function swapEth(bytes calldata data) external payable {
        (uint256 feeAmount, uint256 swapAmount) = calculateAmounts(msg.value);
        payable(feeAddress).sendValue(feeAmount);

        metaRouter.functionCallWithValue(data, swapAmount);

        emit SwapEth(msg.sender, msg.value, tx.origin);
    }

    function calculateAmounts(uint256 fromAmount)
        public
        view
        returns (uint256 feeAmount, uint256 swapAmount)
    {
        feeAmount = (fromAmount * feeRate) / 10000;
        swapAmount = fromAmount - feeAmount;
    }

    function setMetaRouters(address _metaRouter, address _metaRouterGateway)
        external
    {
        require(
            msg.sender == owner,
            "SymbiosisBridge: Only Owner can call this function"
        );

        metaRouter = _metaRouter;
        metaRouterGateway = _metaRouterGateway;
    }

    function withdrawBridgeAssetToken(
        IERC20Upgradeable fromToken,
        address toAddress,
        uint256 tokenAmount
    ) external {
        require(
            msg.sender == owner,
            "SymbiosisBridge: Only Owner can call this function"
        );

        fromToken.transfer(toAddress, tokenAmount);
    }

    function withdrawBridgeAssetEth(address toAddress, uint256 amount)
        external
    {
        require(
            msg.sender == owner,
            "SymbiosisBridge: Only Owner can call this function"
        );

        payable(toAddress).sendValue(amount);
    }
}

