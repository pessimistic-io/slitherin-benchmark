// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC721AUpgradeable.sol";
import "./TwoStage.sol";
import "./AddressUpgradeable.sol";

contract HelixLand is TwoStage {
/*
    HELIX Legal Terms
    1. HELIX Terms of Service [https://helixmetaverse.com/tos/]
    2. HELIX Privacy Policy [https://helixmetaverse.com/privacy/]
*/

  bool public founderPassSaleLive;
  IERC721AUpgradeable public founderPass;
  mapping (uint256 => bool) private _claimed;

  function initialize(
    IERC721AUpgradeable _founderPass,
    string memory prefix_,
    bytes32 whitelistMerkleTreeRoot_,
    address royaltiesRecipient_,
    uint256 royaltiesValue_,
    address[] memory shareholders_,
    uint256[] memory shares_
  ) public initializerERC721A initializer {
    __ERC721A_init("Helix Land", "Helix Land");
    __Ownable_init();
    __AdminManager_init_unchained();
    __Supply_init_unchained(20000);
    __AdminMint_init_unchained();
    __Whitelist_init_unchained();
    __BalanceLimit_init_unchained();
    __UriManager_init_unchained(prefix_, ".json");
    __Royalties_init_unchained(royaltiesRecipient_, royaltiesValue_);
    __DefaultOperatorFilterer_init();
    __CustomPaymentSplitter_init(shareholders_, shares_);
    updateMerkleTreeRoot(uint8(Stage.Whitelist), whitelistMerkleTreeRoot_);

    // @todo confirm these values with team
    updateBalanceLimit(uint8(Stage.Whitelist), 5);
    updateBalanceLimit(uint8(Stage.Public), 5);
    setPrice(uint8(Stage.Whitelist), 0.15 ether);
    setPrice(uint8(Stage.Public), 0.18 ether);

    founderPass = _founderPass;
  }

  /**
   * @dev before this is toggled, increase supply by 5000
   */
  function useFounderPass(uint256[] calldata ids) external {
    require(founderPassSaleLive, "not live");
    uint256 length = ids.length;
    uint256 total = length;
    for(uint256 i = 0; i < length; ++i) {
      uint256 current = ids[i];
      require(founderPass.ownerOf(current) == msg.sender, "Not Owner");
      if(_claimed[current]) {
        total--;
      } else {
        _claimed[current] = true;
      }
    }
    require(total > 0, "Non claimable");
    _callMint(msg.sender, total);
  }

  function setFounderPass(IERC721AUpgradeable _founderPass) external onlyAdmin {
    founderPass = _founderPass;
  }

  function toggleFounderPassSaleLive() external onlyAdmin {
    founderPassSaleLive = !founderPassSaleLive;
  }

  function claimed(uint256 id) public view returns (bool) {
    return _claimed[id];
  }

  function claimable(uint256[] calldata ids) public view returns (uint256) {
    uint256 length = ids.length;
    uint256 total = length;
    for(uint256 i = 0; i < length; ++i) {
      uint256 current = ids[i];
      if(_claimed[current]) {
        total--;
      }
    }
    return total;
  }
}
