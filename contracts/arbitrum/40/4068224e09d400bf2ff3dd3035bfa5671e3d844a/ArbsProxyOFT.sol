// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OFTCore.sol";
import "./SafeERC20.sol";

/**
                       &GJ7P         P7JG&        
                &    &57JG&           &GJ75&    & 
               J7B  B77B                 B77B  B7J
               ?7P &77&                   &77& 57J
               &Y75J75    &#         #&    Y7JY7Y&
                 &PY7?&  P7J&       &J7P  &?7YP&  
                    B?7G&?7G         G7?&G7?B     
                      BY777?J???????J?777YB       
                 &#BBB#G7777777777777777?G#BBB#   
                P777777777???7777777???777777777G 
                Y77777777?!.~???????~.!?77777777Y 
                 #BP77777?~ ^?7!~!7?^ ~?77777PB&  
                   B777777777:     :777777777G    
                   Y7777777?~  :~:  ~?7777777J    
                   J777777777.  .  :777777777?    
                   J77777777??7~^~7?777777777?    
                   Y7777777777?????7777777777J    
                   P7???????????????????????75        

    website : https://arbswap.io
    twitter : https://twitter.com/arbswapofficial
 */
contract ArbsProxyOFT is OFTCore {
    using SafeERC20 for IERC20;

    IERC20 internal immutable innerToken;

    constructor(address _lzEndpoint, address _token) OFTCore(_lzEndpoint) {
        innerToken = IERC20(_token);
    }

    function circulatingSupply() public view virtual override returns (uint) {
        unchecked {
            return innerToken.totalSupply() - innerToken.balanceOf(address(this));
        }
    }

    function token() public view virtual override returns (address) {
        return address(innerToken);
    }

    function _debitFrom(address _from, uint16, bytes memory, uint _amount) internal virtual override returns (uint) {
        require(_from == _msgSender(), "ProxyOFT: owner is not send caller");
        uint before = innerToken.balanceOf(address(this));
        innerToken.safeTransferFrom(_from, address(this), _amount);
        return innerToken.balanceOf(address(this)) - before;
    }

    function _creditTo(uint16, address _toAddress, uint _amount) internal virtual override returns (uint) {
        uint before = innerToken.balanceOf(_toAddress);
        innerToken.safeTransfer(_toAddress, _amount);
        return innerToken.balanceOf(_toAddress) - before;
    }
}

