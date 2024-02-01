// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;
import "./D4AProject.sol";
import "./D4ACanvas.sol";
import "./D4APrice.sol";
import "./D4AReward.sol";

abstract contract ID4AProtocol{
  using D4AProject for mapping(bytes32=>D4AProject.project_info);
  using D4ACanvas for mapping(bytes32=>D4ACanvas.canvas_info);
  using D4APrice for mapping(bytes32=>D4APrice.project_price_info);
  using D4AReward for mapping(bytes32=>D4AReward.reward_info);

  mapping (bytes32=>D4AProject.project_info) public all_projects;
  mapping (bytes32=>D4ACanvas.canvas_info) public all_canvases;
  mapping (bytes32=>D4APrice.project_price_info) public all_prices;
  mapping (bytes32=>D4AReward.reward_info) public all_rewards;
  mapping (bytes32=> bytes32) public tokenid_2_canvas;

  ID4ASetting public settings;

  function createProject(uint256 _start_prb,
                         uint256 _mintable_rounds,
                         uint256 _floor_price_rank,
                         uint256 _max_nft_rank,
                         uint96 _royalty_fee,
                         string memory _project_uri) virtual external payable returns(bytes32 project_id);

  function createOwnerProject(uint256 _start_prb,
                         uint256 _mintable_rounds,
                         uint256 _floor_price_rank,
                         uint256 _max_nft_rank,
                         uint96 _royalty_fee,
                         string memory _project_uri,
                         uint256 _project_index) virtual external payable returns(bytes32 project_id);

  function getProjectCanvasAt(bytes32 _project_id, uint256 _index) public view returns(bytes32){
    return all_projects.getProjectCanvasAt(_project_id, _index);
  }

  function getProjectInfo(bytes32 _project_id) public view
    returns(uint256 start_prb, uint256 mintable_rounds, uint256 floor_price_rank,
                                  uint256 max_nft_amount, address fee_pool, uint96 royalty_fee, uint256 index, string memory uri, uint256 erc20_total_supply){
    return all_projects.getProjectInfo(_project_id);
  }
  function getProjectTokens(bytes32 _project_id) public view returns(address erc20_token, address erc721_token){
    erc20_token = all_projects[_project_id].erc20_token;
    erc721_token = all_projects[_project_id].erc721_token;
  }

  function getCanvasNFTCount(bytes32 _canvas_id) public view returns(uint256){
    return all_canvases.getCanvasNFTCount(_canvas_id);
  }
  function getTokenIDAt(bytes32 _canvas_id, uint256 _index) public view returns(uint256){
    return all_canvases.getTokenIDAt(_canvas_id, _index);
  }
  function getCanvasProject(bytes32 _canvas_id) public view returns(bytes32){
    return all_canvases[_canvas_id].project_id;
  }
  function getCanvasIndex(bytes32 _canvas_id) public view returns(uint256){
    return all_canvases[_canvas_id].index;
  }
  function getCanvasURI(bytes32 _canvas_id) public view returns(string memory){
    return all_canvases.getCanvasURI(_canvas_id);
  }
  function getCanvasLastPrice(bytes32 _canvas_id) public view returns(uint256 round, uint256 price){
    bytes32 proj_id = all_canvases[_canvas_id].project_id;
    return all_prices.getCanvasLastPrice(proj_id, _canvas_id);
  }
  function getCanvasNextPrice(bytes32 _canvas_id) public view returns(uint256){
    bytes32 project_id = all_canvases[_canvas_id].project_id;
    D4AProject.project_info storage pi = all_projects[project_id];
    return all_prices.getCanvasNextPrice(settings, pi.floor_prices, pi.floor_price_rank, pi.start_prb, project_id, _canvas_id);
  }
}

