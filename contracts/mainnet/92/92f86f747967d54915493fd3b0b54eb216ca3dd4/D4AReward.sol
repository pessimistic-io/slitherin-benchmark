// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;
import "./ID4ASetting.sol";
import "./D4AFeePool.sol";

import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";

interface ID4AMintableERC20{
  function mint(address to, uint256 amount) external;
  function burn(address from, uint256 amount) external;
}

library D4AReward{
  using SafeERC20Upgradeable for IERC20Upgradeable;
  struct reward_info{
    uint256[] active_rounds;
    uint256 to_issue_round_index;
    uint256 final_issued_round_index;
    uint256 project_owner_to_claim_round_index;
    uint256 issued_rounds;
    mapping (uint256=>uint256) round_2_total_amount;
    mapping (bytes32=>uint256) canvas_2_to_claim_round_index;
    mapping(bytes32=>mapping(uint256=>uint256)) canvas_2_block_2_amount;
    mapping(bytes32=>uint256) canvas_2_unclaimed_amount;
  }

  function issueTokenToCurrentRound(mapping(bytes32=>reward_info) storage all_rewards,
                                   ID4ASetting _settings,
                                   bytes32 _project_id,
                                   address erc20_token,
                                   uint256 _start_round,
                                   uint256 total_rounds,
                                   uint256 erc20_total_supply) internal returns(uint256){
    ID4APRB prb = _settings.PRB();
    uint256 cur_round = prb.currentRound();
    if(cur_round <= _start_round){
      return 0;
    }
    reward_info storage ri = all_rewards[_project_id];

    uint256 n = ri.issued_rounds;
    if(n >= total_rounds){
      return 0;
    }
    {
      uint i = 0;
      for(i = ri.to_issue_round_index ; i < ri.active_rounds.length; i++){
        if(ri.active_rounds[i] == cur_round){
          break;
        }
        if(all_rewards[_project_id].round_2_total_amount[ri.active_rounds[i]] != 0){
          n = n + 1;
          all_rewards[_project_id].final_issued_round_index = i;
          all_rewards[_project_id].to_issue_round_index = i + 1;
          if(n == total_rounds){
            break;
          }
        }
      }
    }


    uint256 amount = (n - all_rewards[_project_id].issued_rounds) * erc20_total_supply / total_rounds;

    if (amount > 0) ID4AMintableERC20(erc20_token).mint(address(this),  amount);
    all_rewards[_project_id].issued_rounds = n;
    return amount;
  }

  function updateMintWithAmount(mapping(bytes32=>reward_info) storage all_rewards,
                             ID4ASetting _settings,
                             bytes32 _project_id, bytes32 _canvas_id, uint256 _amount, uint256 _eth_amount, uint256 total_rounds,
                             mapping (bytes32 => mapping (uint256 => uint256)) storage round_2_total_eth) internal {
    ID4APRB prb = _settings.PRB();
    uint256 cur_round = prb.currentRound();

    reward_info storage ri = all_rewards[_project_id];
    if (ri.active_rounds.length !=0 && ri.active_rounds[ri.active_rounds.length - 1] != cur_round){
      require(ri.active_rounds.length < total_rounds, "rounds end, cannot mint");
    }

    ri.round_2_total_amount[cur_round] += _amount;
    ri.canvas_2_block_2_amount[_canvas_id][cur_round] += _amount;
    round_2_total_eth[_project_id][cur_round] += _eth_amount;
    if(ri.active_rounds.length == 0){
      ri.active_rounds.push(cur_round);
    }else{
      if(ri.active_rounds[ri.active_rounds.length - 1] != cur_round){
        ri.active_rounds.push(cur_round);
      }
    }
  }

  function claimCanvasReward(mapping(bytes32=>reward_info) storage all_rewards,
                             ID4ASetting _settings,
                             bytes32 _project_id,
                             bytes32 _canvas_id,
                             address _erc20_token,
                             uint256 _start_round,
                             uint256 _total_rounds,
                             uint256 erc20_total_supply) internal returns(uint256){
      updateRewardForCanvas(all_rewards, _settings, _project_id, _canvas_id, _start_round, _total_rounds, erc20_total_supply);
      reward_info storage ri = all_rewards[_project_id];
      uint256 total_amount = ri.canvas_2_unclaimed_amount[_canvas_id];
      ri.canvas_2_unclaimed_amount[_canvas_id] = 0;

      if(total_amount > 0){
        address canvas_owner = _settings.owner_proxy().ownerOf(_canvas_id);
        IERC20Upgradeable(_erc20_token).safeTransfer(canvas_owner, total_amount);
      }
    return total_amount;
  }

  function updateRewardForCanvas(mapping(bytes32=>reward_info) storage all_rewards,
                                 ID4ASetting _settings,
                                 bytes32 _project_id,
                                 bytes32 _canvas_id, uint256 _start_round, uint256 _total_rounds, uint256 erc20_total_supply) internal{
    uint256 cur_round;
    {
      ID4APRB prb = _settings.PRB();
      cur_round = prb.currentRound();
    }

    if(cur_round == _start_round){
      return ;
    }

    uint256 total_amount = 0;
    {
      reward_info storage ri = all_rewards[_project_id];
      if(ri.active_rounds.length == 0){
        return ;
      }
      if(ri.active_rounds.length <= ri.canvas_2_to_claim_round_index[_canvas_id]){
        return ;
      }

      uint256 tk =
        erc20_total_supply * _settings.canvas_erc20_ratio() /(_settings.ratio_base() *_total_rounds);

      for(uint256 i = ri.canvas_2_to_claim_round_index[_canvas_id]; i <= ri.final_issued_round_index; i++){
        if(ri.active_rounds[i] == cur_round){
          break;
        }
        total_amount += tk * ri.canvas_2_block_2_amount[_canvas_id][ri.active_rounds[i]]/
          ri.round_2_total_amount[ri.active_rounds[i]] ;
        ri.canvas_2_to_claim_round_index[_canvas_id] = i + 1;
      }

      ri.canvas_2_unclaimed_amount[_canvas_id] += total_amount;
    }
  }

  function claimCanvasRewardWithETH(
                             ID4ASetting _settings,
                             bytes32 _project_id,
                             bytes32 _canvas_id,
                             address erc20_token,
                             uint256 erc20_amount,
                             address _fee_pool,
                             mapping (bytes32 => mapping (uint256 => uint256)) storage round_2_total_eth) internal returns(uint256){
      if (erc20_amount == 0) return 0;
      address _owner = _settings.owner_proxy().ownerOf(_canvas_id);
      uint256 to_send = sendETH(_settings, erc20_token, _fee_pool, _project_id, _owner, _owner, erc20_amount, round_2_total_eth);
      return to_send;
  }
  function claimProjectReward(mapping(bytes32=>reward_info) storage all_rewards,
                             ID4ASetting _settings,
                             bytes32 _project_id,
                             address erc20_token,
                             uint256 _start_round,
                             uint256 _total_rounds,
                             uint256 erc20_total_supply) internal
    returns(uint256){
    reward_info storage ri = all_rewards[_project_id];
    if(ri.active_rounds.length == 0){
      return 0;
    }
    if(ri.active_rounds.length <= ri.project_owner_to_claim_round_index){
      return 0;
    }

    uint256 from = ri.active_rounds[ri.project_owner_to_claim_round_index];
    if(from == 0){
      from = _start_round;
    }
    ID4APRB prb = _settings.PRB();
    uint256 cur_round = prb.currentRound();
    if(from == cur_round){
      return 0;
    }

    uint256 n = ri.final_issued_round_index - ri.project_owner_to_claim_round_index + 1;
    ri.project_owner_to_claim_round_index = ri.final_issued_round_index + 1;

    uint256 d4a_amount =
      erc20_total_supply * _settings.d4a_erc20_ratio() * n /(_settings.ratio_base() *_total_rounds);
    uint256 project_amount =
      erc20_total_supply * _settings.project_erc20_ratio() * n /(_settings.ratio_base() *_total_rounds);

    if(project_amount != 0){
      address project_owner = _settings.owner_proxy().ownerOf(_project_id);
      IERC20Upgradeable(erc20_token).safeTransfer(project_owner, project_amount);
    }
    if(d4a_amount != 0){
      IERC20Upgradeable(erc20_token).safeTransfer(_settings.protocol_fee_pool(), d4a_amount);
    }
    return project_amount;
  }
  event D4AExchangeERC20ToETH(bytes32 project_id, address owner, address to, uint256 erc20_amount, uint256 eth_amount);

  function claimProjectERC20RewardWithETH(
                             ID4ASetting _settings,
                             bytes32 _project_id,
                             address erc20_token,
                             uint256 erc20_amount,
                             address _fee_pool,
                             mapping (bytes32 => mapping (uint256 => uint256)) storage round_2_total_eth) internal
    returns(uint256){
      if (erc20_amount == 0) return 0;
      address _owner = _settings.owner_proxy().ownerOf(_project_id);
      uint256 to_send = sendETH(_settings, erc20_token, _fee_pool, _project_id, _owner, _owner, erc20_amount, round_2_total_eth);
      return to_send;
  }

  function sendETH(ID4ASetting _settings,
                   address erc20_token, address fee_pool, bytes32 project_id, address _owner, address _to, uint256 erc20_amount,
                   mapping (bytes32 => mapping (uint256 => uint256)) storage round_2_total_eth)
    internal returns(uint256){
      ID4AMintableERC20(erc20_token).burn(_owner, erc20_amount);
      ID4AMintableERC20(erc20_token).mint(fee_pool, erc20_amount);

      ID4APRB prb = _settings.PRB();
      uint256 cur_round = prb.currentRound();

      uint256 circulate_erc20 = IERC20Upgradeable(erc20_token).totalSupply() + erc20_amount - IERC20Upgradeable(erc20_token).balanceOf(fee_pool);
      if (circulate_erc20 == 0) return 0;
      uint256 avaliable_eth = fee_pool.balance - round_2_total_eth[project_id][cur_round];
      uint256 to_send = erc20_amount * avaliable_eth / circulate_erc20;
      if(to_send != 0){
        D4AFeePool(payable(fee_pool)).transfer(address(0x0), payable(_to), to_send);
      }
      emit D4AExchangeERC20ToETH(project_id, _owner, _to, erc20_amount, to_send);
      return to_send;
  }

  function ToETH(ID4ASetting _settings, address erc20_token, address fee_pool,
                 bytes32 project_id, address _owner, address _to, uint256 amount,
                 mapping (bytes32 => mapping (uint256 => uint256)) storage round_2_total_eth)
    internal returns(uint256){
    return sendETH(_settings, erc20_token, fee_pool, project_id, _owner, _to, amount, round_2_total_eth);
  }

}

