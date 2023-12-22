// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./OwnableUpgradeable.sol";
import "./Clones.sol";

interface IBribe {
    function addReward(address) external;
    function addRewardTokens (address[] memory) external;
    function initialize(address,address,address,string memory,bool) external;

}

contract BribeFactoryV3 is OwnableUpgradeable {
    
    uint256[50] __gap;
    
    address public last_bribe;
    address public voter;
    address public bribeImplementation;

    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _voter, address _bribeImplementation) initializer  public {
        __Ownable_init();
        voter = _voter;
        bribeImplementation = _bribeImplementation;
    }

    function createBribe(address _owner,address _token0,address _token1, string memory _type, bool _internal) external returns (address) {
        require(msg.sender == voter || msg.sender == owner(), 'only voter');

        last_bribe = Clones.clone(bribeImplementation);
        IBribe(last_bribe).initialize(_owner, voter, address(this), _type, _internal);
        if (_internal) {
            address[] memory tokens = new address[](2);

            tokens[0] = _token0;
            tokens[1] = _token1;
            IBribe(last_bribe).addRewardTokens(tokens);
        }

        return last_bribe;
    }

    function setVoter(address _Voter) external {
        require(owner() == msg.sender, 'not owner');
        require(_Voter != address(0));
        voter = _Voter;
    }

     function addRewards(address _token, address[] memory _bribes) external {
        require(owner() == msg.sender, 'not owner');
        uint i = 0;
        for ( i ; i < _bribes.length; i++){
            IBribe(_bribes[i]).addReward(_token);
        }

    }

    function addRewards(address[][] memory _token, address[] memory _bribes) external {
        require(msg.sender == voter || msg.sender == owner(), 'only voter or owner');

        uint i = 0;
        for ( i ; i < _bribes.length; i++){
            IBribe( _bribes[i] ).addRewardTokens(_token[i]);
        }

    }

}
