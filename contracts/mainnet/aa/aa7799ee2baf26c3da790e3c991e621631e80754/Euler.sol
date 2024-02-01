// 3e5de45653758f55a3ad26a8514371f4f4c433e4
pragma solidity ^0.8.0;

import "./ACLBase.sol";

contract EulerACL is ACLBase{
	string public constant override NAME = "EulerACL";
	uint public constant override VERSION = 1;

	struct EulerBatchItem {
        bool allowError;
        address proxyAddr;
        bytes data;
    }

    bytes4 internal constant depositSelector = 0xe2bbb158;
    bytes4 internal constant withdrawSelector = 0x441a3e70;
    mapping(bytes4 => bool) internal allowedSelector;

    function checkSelector(bytes4 _selector) public view returns(bool){
    	if (_selector == depositSelector || _selector == withdrawSelector){
    		return true;
    	}else{
    		return allowedSelector[_selector];
    	}
    }

    function setAllowedSelector(bytes4 _selector, bool _status) external onlySafe {
    	if(_selector == depositSelector || _selector == withdrawSelector){
    		return;
    	}
    	allowedSelector[_selector] = _status;
    }


	function batchDispatch(EulerBatchItem[] calldata _items, address[] calldata) external onlySelf{
		require(_items.length == 1, "Only one operation allowed");
		bytes4 _selector = bytes4(_items[0].data[:4]);
		require(checkSelector(_selector), "Operation not allowed");
	}
}
