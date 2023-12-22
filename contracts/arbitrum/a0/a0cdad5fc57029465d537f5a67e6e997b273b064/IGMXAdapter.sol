pragma solidity 0.6.10;

interface IGMXAdapter{
  struct IncreasePositionRequest{
    address[]  _path;
    address _indexToken;
    uint256 _amountIn;
    uint256 _minOut;
    uint256 _sizeDelta;
    bool _isLong;
    uint256 _acceptablePrice;
    uint256 _executionFee;
    bytes32 _referralCode;
    address _callbackTarget;
  }
  struct DecreasePositionRequest{
    address[]  _path;
    address _indexToken;
    uint256 _collateralDelta;
    uint256 _sizeDelta;
    bool _isLong;
    address _receiver;
    uint256 _acceptablePrice;
    uint256 _minOut;
    uint256 _executionFee;
    bool _withdrawETH;
    address _callbackTarget;
  }
}

