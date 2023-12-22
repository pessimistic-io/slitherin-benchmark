// SPDX-License-Identifier: MIT
/*
                                                     _..._                                                                                                               __               
                                                  .-'_..._''.                                                                                                       ...-'  |`.            
                                                .' .'      '.\    .                      _________   _...._                       __.....__                         |      |  |           
       _     _                _.._             / .'             .'|                      \        |.'      '-.                .-''         '.                       ....   |  |    ,.--.  
 /\    \\   //      .|      .' .._|           . '              <  |                       \        .'```'.    '.      .|     /     .-''"'-.  `.  .-,.--.              -|   |  |   //    \ 
 `\\  //\\ //     .' |_     | '               | |               | |               __       \      |       \     \   .' |_   /     /________\   \ |  .-. |              |   |  |   \\    / 
   \`//  \'/    .'     |  __| |__             | |               | | .'''-.     .:--.'.      |     |        |    | .'     |  |                  | | |  | |           ...'   `--'    `'--'  
    \|   |/    '--.  .-' |__   __|            . '               | |/.'''. \   / |   \ |     |      \      /    . '--.  .-'  \    .-------------' | |  | |           |         |`.  ,.--.  
     '            |  |      | |                \ '.          .  |  /    | |   `" __ | |     |     |\`'-.-'   .'     |  |     \    '-.____...---. | |  '-            ` --------\ | //    \ 
                  |  |      | |                 '. `._____.-'/  | |     | |    .'.''| |     |     | '-....-'`       |  |      `.             .'  | |                 `---------'  \\    / 
                  |  '.'    | |                   `-.______ /   | |     | |   / /   | |_   .'     '.                |  '.'      `''-...... -'    | |                               `'--'  
                  |   /     | |                            `    | '.    | '.  \ \._,\ '/ '-----------'              |   /                        |_|                                      
                  `'-'      |_|                                 '---'   '---'  `--'  `"                             `'-'                                                                  


                  .                                                                         |   |                            .--.                                             .--.             _..._           __.....__                              
       _     _  .'|                                                                         |   |  .-.          .-           |__|                            _.._             |__|           .'     '.     .-''         '.                            
 /\    \\   // <  |                           .|                  .|   .-,.--.              |   |   \ \        / /           .--.                          .' .._|            .--. .-,.--.  .   .-.   .   /     .-''"'-.  `.                          
 `\\  //\\ //   | |               __        .' |_               .' |_  |  .-. |             |   |    \ \      / /            |  |                          | '         __     |  | |  .-. | |  '   '  |  /     /________\   \                         
   \`//  \'/    | | .'''-.     .:--.'.    .'     |            .'     | | |  | |    _    _   |   |     \ \    / /             |  |        _               __| |__    .:--.'.   |  | | |  | | |  |   |  |  |                  |        _           _    
    \|   |/     | |/.'''. \   / |   \ |  '--.  .-'           '--.  .-' | |  | |   | '  / |  |   |      \ \  / /              |  |      .' |             |__   __|  / |   \ |  |  | | |  | | |  |   |  |  \    .-------------'      .' |        .' |   
     '          |  /    | |   `" __ | |     |  |                |  |   | |  '-   .' | .' |  |   |       \ `  /               |  |     .   | /              | |     `" __ | |  |  | | |  '-  |  |   |  |   \    '-.____...---.     .   | /     .   | / 
                | |     | |    .'.''| |     |  |                |  |   | |       /  | /  |  |   |        \  /                |__|   .'.'| |//              | |      .'.''| |  |__| | |      |  |   |  |    `.             .'    .'.'| |//   .'.'| |// 
                | |     | |   / /   | |_    |  '.'              |  '.' | |      |   `'.  |  '---'        / /                      .'.'.-'  /               | |     / /   | |_      | |      |  |   |  |      `''-...... -'    .'.'.-'  /  .'.'.-'  /  
                | '.    | '.  \ \._,\ '/    |   /               |   /  |_|      '   .'|  '/          |`-' /                       .'   \_.'                | |     \ \._,\ '/      |_|      |  |   |  |                       .'   \_.'   .'   \_.'   
                '---'   '---'  `--'  `"     `'-'                `'-'             `-'  `--'            '..'                                                 |_|      `--'  `"                '--'   '--'                                               

*/

pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract WTFTOKEN is ERC20, Pausable, Ownable {
    mapping(address => bool) private _unrestrictedAddresses;

    constructor() ERC20("WTF", "WTF") {
        _mint(msg.sender, 210000000000000 * 10 ** decimals());
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function addUnrestrictedAddress(address unrestrictedAddress) public onlyOwner {
        _unrestrictedAddresses[unrestrictedAddress] = true;
    }

    function removeUnrestrictedAddress(address unrestrictedAddress) public onlyOwner {
        _unrestrictedAddresses[unrestrictedAddress] = false;
    }

    function isUnrestrictedAddress(address addr) public view returns (bool) {
        return _unrestrictedAddresses[addr];
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPausedOrUnrestricted(from)
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    modifier whenNotPausedOrUnrestricted(address addr) {
        require(!paused() || isUnrestrictedAddress(addr), "WTF transfer while paused");
        _;
    }

    function renounceOwnership() public override onlyOwner {
        transferOwnership(address(0));
    }
}

