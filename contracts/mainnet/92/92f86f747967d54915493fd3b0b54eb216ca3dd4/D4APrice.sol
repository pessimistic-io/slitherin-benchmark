// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;
import "./ID4ASetting.sol";

library D4APrice {
  struct last_price{
    uint256 round;
    uint256 value;
  }
  struct project_price_info{
    last_price max_price;
    uint256 price_rank;
    uint256[] price_slots;
    mapping(bytes32=>last_price) canvas_price;
  }

  function getCanvasLastPrice(mapping(bytes32=>project_price_info) storage all_prices,
                              bytes32 _project_id, bytes32 _canvas_id) public view
    returns(uint256 round, uint256 value){
    last_price storage lp = all_prices[_project_id].canvas_price[_canvas_id];
    round = lp.round;
    value = lp.value;
  }

  function getCanvasNextPrice(mapping(bytes32=>project_price_info) storage all_prices,
                              ID4ASetting _settings,
                              uint256[] memory price_slots, uint256 price_rank, uint256 start_prb,
                              bytes32 _project_id, bytes32 _canvas_id) internal view returns(uint256 price){

    uint256 floor_price = price_slots[price_rank];
    project_price_info storage ppi = all_prices[_project_id];
    ID4APRB prb = _settings.PRB();
    uint256 cur_round = prb.currentRound();
    if (ppi.max_price.round == 0){
      if (cur_round == start_prb) return floor_price;
      else return floor_price/2;
    }
    uint256 first_guess = _get_price_in_round(ppi.canvas_price[_canvas_id], cur_round);
    if(first_guess >= floor_price){
      return first_guess;
    }
    /*if(ppi.canvas_price[_canvas_id].round == cur_round ||
      ppi.canvas_price[_canvas_id].round +1 == cur_round){
      return floor_price;
    }*/

    first_guess = _get_price_in_round(ppi.max_price, cur_round);
    if(first_guess >= floor_price){
      return floor_price;
    }
    if (ppi.max_price.value == floor_price/2 && cur_round <= ppi.max_price.round + 1){
      return floor_price;
    }

    return floor_price/2;
  }

  function updateCanvasPrice(mapping(bytes32=>project_price_info) storage all_prices,
                              ID4ASetting _settings,
                              bytes32 _project_id, bytes32 _canvas_id,
                              uint256 price) internal {
    project_price_info storage ppi = all_prices[_project_id];
    ID4APRB prb = _settings.PRB();
    uint256 cp = 0;
    {
      uint256 cur_round = prb.currentRound();
      cp = _get_price_in_round(ppi.max_price, cur_round);
    }
    if(price >= cp){
      ppi.max_price.round = prb.currentRound();
      ppi.max_price.value= price;
    }

    ppi.canvas_price[_canvas_id].round = prb.currentRound();
    ppi.canvas_price[_canvas_id].value = price;
  }

  function _get_price_in_round(last_price memory lp, uint256 round) internal pure returns(uint256){
    if(round == lp.round){
      return lp.value << 1;
    }
    uint256 k = round - lp.round - 1;
    return lp.value >>k;
  }
}

