pragma solidity 0.6.10;
interface IGMXAdapter {

    function ETH_TOKEN() external view returns (address);

    function getInCreasingPositionCallData(
      address _underlyingToken,
      address _indexToken,
      uint256 _underlyingUnits,
      address _to,
      bytes memory _positionData
    ) external view returns (address _subject, uint256 _value, bytes memory _calldata);

    function getDeCreasingPositionCallData(
      address _underlyingToken,
      address _indexToken,
      uint256 _underlyingUnits,
      address _to,
      bytes memory _positionData
    ) external  view returns (address _subject, uint256 _value, bytes memory _calldata);

    function PositionRouter() external view returns(address);
    function OrderBook() external view returns(address);
    function Vault() external view returns(address);
    function GMXRouter() external view returns(address);
    function getTokenBalance(address _token, address _jasperVault)external returns(uint256);
    function getCreateDecreaseOrderCallData( bytes calldata _data)external view  returns (address, uint256, bytes memory);
    function getCreateIncreaseOrderCallData( bytes calldata _data)external view  returns (address, uint256, bytes memory);
    function getSwapCallData( bytes calldata _swapData )external view  returns (address, uint256, bytes memory);
    function approvePositionRouter()external view  returns (address, uint256, bytes memory);
}

