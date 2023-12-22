//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./FragmentSwapperContracts.sol";

contract FragmentSwapper is Initializable, FragmentSwapperContracts {

    function initialize() external initializer {
        FragmentSwapperContracts.__FragmentSwapperContracts_init();
    }

    function swapFragments(
        SwapParams[] calldata _params)
    external
    contractsAreSet
    whenNotPaused
    {
        require(_params.length > 0, "FragmentSwapper: Bad length");

        for(uint256 i = 0; i < _params.length; i++) {
            SwapParams calldata _param = _params[i];
            require(_param.fragmentId > 5 && _param.fragmentId < 16,
                "FragmentSwapper: Bad fragment id");
            require(_param.amount > 0, "FragmentSwapper: Bad amount");

            treasureFragment.burn(msg.sender, _param.fragmentId, _param.amount);

            uint128 _newFragmentId;
            if(_param.fragmentId < 11) {
                _newFragmentId = _param.fragmentId + 5;
            } else {
                _newFragmentId = _param.fragmentId - 5;
            }

            treasureFragment.mint(msg.sender, _newFragmentId, _param.amount);
        }
    }
}

struct SwapParams {
    uint128 fragmentId;
    uint128 amount;
}
