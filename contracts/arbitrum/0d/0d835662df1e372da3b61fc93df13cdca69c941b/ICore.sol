// write interface for
//Interface
interface ICore {
  function ownerOf(uint256 id) external view returns (address);

  function uri(uint256 id) external view returns (string memory);

  function modularMintInit(
    uint256 _dropId,
    address _to,
    bytes memory _data,
    address _validator,
    string calldata _metadata
  ) external;

  function modularMintCallback(
    address recipient,
    uint256 _id,
    bytes calldata _data
  ) external;
}

