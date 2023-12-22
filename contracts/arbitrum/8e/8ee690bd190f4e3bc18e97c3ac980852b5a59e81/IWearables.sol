// Dev Note: collapse these down into composable interfaces?
interface IWearables {

  function id(string calldata cid) external returns(uint32);
  
  function getSlot(string calldata _cid) external returns(uint16);

  function getEquipmentFromPill(uint256 pillId, uint256 form) external view returns (string[] memory);
  
  function mintEquipment(address target, uint256 item) external;

}

