pragma solidity ^0.8.0;

import "./Ownable.sol";

// components
// *** items id 1000-1999 ***

// 1000 - 1449 : Profession items (9 Professions)
// 0-49 Profession 1
// 0-29 basic compo
// 30-49 craftable compo
// Find a Profession item: itemId = (50 * ProfessonId) + index

// 1500 - 1999 : Structure items
contract Craftbook is Ownable{

    mapping (uint256 => string) names;

    function getName(uint256 _id) external view returns(string memory){
        return names[_id];
    }

    function addItems(uint256[] memory _ids, string[] memory _names) external onlyOwner{
        for(uint i=0;i<_ids.length;i++){
            names[_ids[i]] = _names[i];
        }
    }

}
