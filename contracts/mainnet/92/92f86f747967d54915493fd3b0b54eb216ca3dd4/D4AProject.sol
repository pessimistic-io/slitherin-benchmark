// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;
import "./ID4ASetting.sol";
import "./ID4AChangeAdmin.sol";
import "./D4AERC721.sol";
import "./D4AFeePool.sol";
import "./D4AERC20.sol";

import "./StringsUpgradeable.sol";

library D4AProject{
  struct project_info{
    uint256 start_prb;
    uint256 mintable_rounds;
    uint256 floor_price_rank;
    uint256 max_nft_amount;
    uint256 nft_supply;
    uint96 royalty_fee;
    uint256 index;
    address erc20_token;
    address erc721_token;
    address fee_pool;
    string project_uri;
    //from setting
    uint256 erc20_total_supply;
    uint256[] floor_prices;
    bytes32[] canvases;
    bool exist;
  }

  using StringsUpgradeable for uint256;

  error D4AInsufficientEther(uint256 required);
  error D4AProjectAlreadyExist(bytes32 project_id);
  event NewProject(bytes32 project_id, string uri, address fee_pool, address erc20_token, address erc721_token, uint256 royalty_fee);

  function createProject(mapping(bytes32=>project_info) storage all_projects,
                         ID4ASetting _settings,
                        uint256 _start_prb,
                         uint256 _mintable_rounds,
                         uint256 _floor_price_rank,
                         uint256 _max_nft_rank,
                         uint96 _royalty_fee,
                         uint256 _project_index,
                         string memory _project_uri) public returns(bytes32 project_id){
    require(_settings.project_max_rounds() >= _mintable_rounds, "rounds too long, not support");
    {
      uint256 protocol_fee = _settings.mint_d4a_fee_ratio();
      require(_royalty_fee >= _settings.rf_lower_bound() + protocol_fee && _royalty_fee <= _settings.rf_upper_bound() + protocol_fee, "royalty fee out of range");
    }
    {
      uint256 minimal = _settings.create_project_fee();
      require(msg.value >= minimal, "not enough ether to create project");
      (bool succ, ) = _settings.protocol_fee_pool().call{value:minimal}("");
      require(succ, "transfer fee failed");
      uint256 exchange = msg.value - minimal;
      if(exchange != 0){
        (succ, ) = msg.sender.call{value:exchange}("");
        require(succ, "transfer exchange failed");
      }
    }

    project_id = keccak256(abi.encodePacked(block.number, msg.sender, msg.data, tx.origin));


    if(all_projects[project_id].exist) revert D4AProjectAlreadyExist(project_id);
    {
      project_info storage pi = all_projects[project_id];
      pi.start_prb= _start_prb;
      {
        ID4APRB prb = _settings.PRB();
        uint256 cur_round = prb.currentRound();
        require(_start_prb >= cur_round, "start round already passed");
      }
      pi.mintable_rounds = _mintable_rounds;
      pi.floor_price_rank = _floor_price_rank;
      pi.max_nft_amount = _settings.max_nft_amounts(_max_nft_rank);
      pi.project_uri = _project_uri;
      pi.royalty_fee = _royalty_fee;
      pi.index = _project_index;
      pi.erc20_token = _createERC20Token(_settings, _project_index);

      D4AERC20(pi.erc20_token).grantRole(keccak256("MINTER"), address(this));
      D4AERC20(pi.erc20_token).grantRole(keccak256("BURNER"), address(this));

      address pool= _settings.feepool_factory().createD4AFeePool(
      string(abi.encodePacked("Asset Pool for DAO4Art Project ", _project_index.toString())));


      D4AFeePool(payable(pool)).grantRole(keccak256("AUTO_TRANSFER"), address(this));

      ID4AChangeAdmin(pool).changeAdmin(_settings.asset_pool_owner());
      ID4AChangeAdmin(pi.erc20_token).changeAdmin(_settings.asset_pool_owner());

      pi.fee_pool = pool;

      _settings.owner_proxy().initOwnerOf(project_id, msg.sender);

      pi.erc721_token = _createERC721Token(_settings, _project_index);
      D4AERC721(pi.erc721_token).grantRole(keccak256("ROYALTY"), address(this));
      D4AERC721(pi.erc721_token).setRoyaltyInfo(pi.fee_pool, _royalty_fee);
      D4AERC721(pi.erc721_token).grantRole(keccak256("MINTER"), address(this));

      D4AERC721(pi.erc721_token).setContractUri(_project_uri);
      ID4AChangeAdmin(pi.erc721_token).changeAdmin(_settings.asset_pool_owner());
      ID4AChangeAdmin(pi.erc721_token).transferOwnership(msg.sender);
      //We copy from setting in case setting may change later.
      pi.erc20_total_supply = _settings.erc20_total_supply();
      for(uint i = 0; i < _settings.floor_prices_length(); i++){
        pi.floor_prices.push(_settings.floor_prices(i));
      }
      require(pi.floor_price_rank < pi.floor_prices.length, "invalid floor price rank");

      pi.exist = true;
      emit NewProject(project_id, _project_uri, pool, pi.erc20_token, pi.erc721_token, _royalty_fee);
    }
  }


  function getProjectCanvasCount(mapping(bytes32=>project_info) storage all_projects,
                          bytes32 _project_id) internal view returns(uint256){

    project_info storage pi = all_projects[_project_id];
    return pi.canvases.length;
  }
  function getProjectCanvasAt(mapping(bytes32=>project_info) storage all_projects,
                              bytes32 _project_id, uint256 _index) internal view returns(bytes32){
    project_info storage pi = all_projects[_project_id];
    return pi.canvases[_index];
  }
  function getProjectInfo(mapping(bytes32=>project_info) storage all_projects,
                          bytes32 _project_id) internal view
                          returns(uint256 start_prb, uint256 mintable_rounds, uint256 floor_price_rank,
                                  uint256 max_nft_amount, address fee_pool, uint96 royalty_fee, uint256 index, string memory uri, uint256 erc20_total_supply){
    project_info storage pi = all_projects[_project_id];
    start_prb = pi.start_prb;
    mintable_rounds = pi.mintable_rounds;
    floor_price_rank = pi.floor_price_rank;
    max_nft_amount = pi.max_nft_amount;
    fee_pool = pi.fee_pool;
    royalty_fee = pi.royalty_fee;
    index = pi.index;
    uri = pi.project_uri;
    erc20_total_supply = pi.erc20_total_supply;
  }

  /*function toHex16 (bytes16 data) internal pure returns (bytes32 result) {
    result = bytes32 (data) & 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000 |
            (bytes32 (data) & 0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >> 64;
    result = result & 0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000 |
            (result & 0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >> 32;
    result = result & 0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000 |
            (result & 0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >> 16;
    result = result & 0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000 |
            (result & 0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >> 8;
    result = (result & 0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >> 4 |
            (result & 0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >> 8;
    result = bytes32 (0x3030303030303030303030303030303030303030303030303030303030303030 +
            uint256 (result) +
            (uint256 (result) + 0x0606060606060606060606060606060606060606060606060606060606060606 >> 4 &
            0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) * 7);

  }

  function toHex (bytes32 data) internal pure returns (string memory) {
    return string (abi.encodePacked (toHex16 (bytes16 (data)), toHex16 (bytes16 (data << 128))));
  }
  function subString(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
    bytes memory strBytes = bytes(str);
    bytes memory result = new bytes(endIndex-startIndex);
    for(uint i = startIndex; i < endIndex; i++) {
          result[i-startIndex] = strBytes[i];
    }
    return string(result);
  }*/

  function _createERC20Token(ID4ASetting _settings, uint256 _project_num) internal returns(address){
    string memory name = string(abi.encodePacked("D4A Token for D4A@", _project_num.toString()));
    string memory sym = string(abi.encodePacked("D4A_T ", _project_num.toString()));
    return _settings.erc20_factory().createD4AERC20(name, sym, address(this));
  }

  function _createERC721Token(ID4ASetting _settings, uint256 _project_num) internal returns(address){
    string memory name = string(abi.encodePacked("D4A NFT for D4A@", _project_num.toString()));
    string memory sym = string(abi.encodePacked("D4A_N ", _project_num.toString()));
    return _settings.erc721_factory().createD4AERC721(name, sym);
  }
}

