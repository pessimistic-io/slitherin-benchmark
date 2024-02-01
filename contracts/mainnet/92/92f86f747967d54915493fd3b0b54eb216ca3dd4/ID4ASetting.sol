// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;
import "./ID4APRB.sol";
import "./ID4AFeePoolFactory.sol";
import "./ID4AERC20Factory.sol";
import "./ID4AOwnerProxy.sol";
import "./ID4AERC721.sol";
import "./ID4AERC721Factory.sol";

interface ID4AProtocolForSetting {
  function getCanvasProject(bytes32 _canvas_id) external view returns(bytes32);
}

contract ID4ASetting{
  uint256 public ratio_base;
  uint256 public min_stamp_duty; //TODO
  uint256 public max_stamp_duty;

  uint256 public create_project_fee;
  address public protocol_fee_pool;
  uint256 public create_canvas_fee;

  uint256 public mint_d4a_fee_ratio;
  uint256 public trade_d4a_fee_ratio;
  uint256 public mint_project_fee_ratio;

  uint256 public erc20_total_supply;

  uint256 public project_max_rounds; //366

  uint256 public project_erc20_ratio;
  uint256 public canvas_erc20_ratio;
  uint256 public d4a_erc20_ratio;

  uint256 public rf_lower_bound;
  uint256 public rf_upper_bound;
  uint256[] public floor_prices;
  uint256[] public max_nft_amounts;

  ID4APRB public PRB;

  string public erc20_name_prefix;
  string public erc20_symbol_prefix;

  ID4AERC721Factory public erc721_factory;
  ID4AERC20Factory public erc20_factory;
  ID4AFeePoolFactory public feepool_factory;
  ID4AOwnerProxy public owner_proxy;
  ID4AProtocolForSetting public protocol;
  address public asset_pool_owner;

  bool public d4a_pause;

  mapping(bytes32 => bool) public pause_status;

  address public WETH;

  address public project_proxy;

  uint256 public reserved_slots;

  constructor(){
    //some default value here
    ratio_base = 10000;
    create_project_fee = 0.1 ether;
    create_canvas_fee = 0.01 ether;
    mint_d4a_fee_ratio = 250;
    trade_d4a_fee_ratio = 250;
    mint_project_fee_ratio = 3000;
    rf_lower_bound = 500;
    rf_upper_bound = 1000;

    project_erc20_ratio = 300;
    d4a_erc20_ratio = 200;
    canvas_erc20_ratio = 9500;
    project_max_rounds = 366;
    reserved_slots = 110;
  }

  function floor_prices_length() public view returns(uint256){
    return floor_prices.length;
  }
  function max_nft_amounts_length() public view returns(uint256){
    return max_nft_amounts.length;
  }

}

