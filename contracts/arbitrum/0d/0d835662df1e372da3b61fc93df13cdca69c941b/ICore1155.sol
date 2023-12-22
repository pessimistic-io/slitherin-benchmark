// write interface for
//Interface
interface ICore1155 {

  function uri(uint256 id) external view returns (string memory);

  function modularMintCallback(
    address recipient,
    uint256[] calldata _ids,
    uint256[] calldata _requestedAmounts,
    bytes calldata _data
  ) external;
  function modularMintCallbackSingle(
    address recipient,
    uint256 _id,
    bytes calldata _data
  ) external;
}

