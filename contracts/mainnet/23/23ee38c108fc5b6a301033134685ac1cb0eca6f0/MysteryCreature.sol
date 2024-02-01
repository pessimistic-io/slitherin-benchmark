//SPDX-License-Identifier: Unlicense

//              ／＞　 フ  
//             | 　_　_|   
//           ／` ミ＿xノ     made with 🤔 by nbaronia.eth 
//          /　　　　 |      dedicated to the normies - if i can deploy, you can too 🫡  
//         /　 ヽ　　 ﾉ     
//         │　　|　|　|   
//     ／￣|　　|　|　|   
//      (￣ヽ＿_ヽ_)__)
//     ＼二)

pragma solidity >=0.8.12;
import "./Strings.sol";
import "./Ownable.sol";
import {ENSNameResolver} from "./ENSNameResolver.sol";




contract MysteryCreature is Ownable, ENSNameResolver{

   event openMessage(string openStr);

   event closeMessage(string closeStr);

   event namingCeremony(string ritual);
   
   bool public boxIsOpen = false;
   uint public requiredBribe = 1000000000000000;
   string public creature = "Cat";
   string public wisdom = "Meow";
   string public lastNamedBy;


   // Open the box on chain to see what's inside. No cost, only gas fees.
   function openTheBox() external {
      boxIsOpen = true;
      string memory openerENS = ENSNameResolver.getENSName(msg.sender);
      string memory openStr = string.concat(openerENS,
                                            " opened the box and asked, \"Oh great ",
                                            creature,
                                            " of the box, what is your wisdom?\" ");
      emit openMessage(openStr);
      closeTheBox();
   }


   // Automatically close the box on chain after opening it.
   function closeTheBox() private {
      string memory closeStr = string.concat(creature,
                                             " declared \"",
                                             wisdom,
                                             "\", and closed the box. ");
      boxIsOpen = false;
      emit closeMessage(closeStr);
   }


   // Pay a bribe to change the creature's name and wisdom. Initial bribe = .001E
   function name(string memory newCatName, string memory newCatWisdom) external payable {
      require(msg.value >= requiredBribe);
      payable(Ownable.owner()).transfer(msg.value);

      lastNamedBy = ENSNameResolver.getENSName(msg.sender);
      string memory ritual = string.concat(lastNamedBy, 
                                             " performed a super secret naming ceremony, renamed ",
                                             creature, " to ", newCatName, 
                                             ", and whispered new wisdom into its ear." 
        );
      creature = newCatName;
      wisdom = newCatWisdom;

      emit namingCeremony(ritual);
    }


   // Update the required bribe amount to change the creature's attributes.
   function updateBribe(uint newBribe) external {
        require(msg.sender == Ownable.owner(), "You're not my supervisor!");
        requiredBribe = newBribe;
    }


}
