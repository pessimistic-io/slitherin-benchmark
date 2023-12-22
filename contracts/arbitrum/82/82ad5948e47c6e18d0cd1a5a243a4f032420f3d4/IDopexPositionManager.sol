//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// Structs
struct IncreaseOrderParams {
    address[] path;
    address indexToken;
    uint256 collateralDelta;
    uint256 positionSizeDelta;
    uint256 acceptablePrice;
    bool isLong;
}

struct DecreaseOrderParams {
    IncreaseOrderParams orderParams;
    address receiver;
    bool withdrawETH;
}

interface IDopexPositionManager {
    function enableAndCreateIncreaseOrder(
        IncreaseOrderParams calldata params,
        address _gmxVault,
        address _gmxRouter,
        address _gmxPositionRouter,
        address _user
    ) external payable;

    function increaseOrder(IncreaseOrderParams memory _increaseOrderParams) external payable;

    function decreaseOrder(DecreaseOrderParams calldata _decreaseorderParams) external payable;

    function release() external;

    function minSlippageBps() external view returns (uint256);

    function setStrategyController(address _strategy) external;

    function withdrawTokens(
        address[] calldata _tokens,
        address _receiver
    ) external returns (uint256[] memory _amounts);

    function strategyControllerTransfer(
        address _token,
        address _to,
        uint256 amount
    ) external;

    function lock() external;

    function slippage() external view returns (uint256);

    event IncreaseOrderCreated(
        address[] _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _acceptablePrice
    );
    event DecreaseOrderCreated(
        address[] _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _acceptablePrice
    );
    event ReferralCodeSet(bytes32 _newReferralCode);
    event Released();
    event Locked();
    event TokensWithdrawn(address[] tokens, uint256[] amounts);
    event SlippageSet(uint256 _slippage);
    event CallbackSet(address _callback);
    event FactorySet(address _factory);
    event StrategyControllerSet(address _strategy);
}

