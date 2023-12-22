// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./OwnableUpgradeable.sol";
import "./Clones.sol";

interface IBribe {
    function addReward(address) external;
    function addRewardTokens (address[] memory) external;
    function initialize(address,address,string memory,bool) external;
}

interface IBribeFactoryImpl {
    function bribeImplementation () external view returns (address impl);
}

contract BribeProxy {
    address immutable public bribeFactory;

    constructor () {
        bribeFactory = msg.sender;
    }

    /**
     * @dev Returns the current implementation.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     */

    function _dispatchImplementation() private returns (bytes memory) {
        address implementation = IBribeFactoryImpl(bribeFactory).bribeImplementation();
        return abi.encode(implementation);
    }

    fallback () payable external {
        address impl = IBribeFactoryImpl(address(0)).bribeImplementation();
        require(impl != address(0));
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), impl, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}

contract BribeFactoryV3 is OwnableUpgradeable {
    
    uint256[50] __gap;
    
    address public last_bribe;
    address public voter;
    address public bribeImplementation;

    address[] public defaultRewardToken;

    event bribeImplementationChanged( address _oldbribeImplementation, address _newbribeImplementation);

    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _voter, address _bribeImplementation) initializer  public {
        __Ownable_init();
        voter = _voter;

                
        //bribe default tokens
        defaultRewardToken.push(address(0x15b2fb8f08E4Ac1Ce019EADAe02eE92AeDF06851));   // $chr
        defaultRewardToken.push(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));   // $weth
        defaultRewardToken.push(address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));   // $usdc
        defaultRewardToken.push(address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8));   // $usdc.e
        defaultRewardToken.push(address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1));   // $dai
        defaultRewardToken.push(address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f));   // $wbtc


        bribeImplementation = _bribeImplementation;
    }

    function createBribe(address _token0,address _token1, string memory _type, bool _internal) external returns (address) {
        require(msg.sender == voter || msg.sender == owner(), 'only voter');

        last_bribe = address(new BribeProxy());

        IBribe(last_bribe).initialize(voter, address(this), _type, _internal);
        if (_internal) {
            if(_token0 != address(0)) IBribe(last_bribe).addReward(_token0);  
            if(_token1 != address(0)) IBribe(last_bribe).addReward(_token1); 
        } else {
            IBribe(last_bribe).addRewardTokens(defaultRewardToken);    
        }

        return last_bribe;
    }

    function bribeOwner() external view returns (address) {
        return owner();
    }

    function setVoter(address _Voter) external onlyOwner {
        require(_Voter != address(0));
        voter = _Voter;
    }

    function changeImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0));
        emit bribeImplementationChanged(bribeImplementation, _implementation);
        bribeImplementation = _implementation;
    }

     function addRewards(address _token, address[] memory _bribes) external onlyOwner {
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
