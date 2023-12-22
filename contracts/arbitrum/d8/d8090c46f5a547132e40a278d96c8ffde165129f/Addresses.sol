//  SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
 /*
  * @notice Address constants that can be relied upon throughout this repo
  * Any change to where these are located would imply changes made which will require a new deployment anyways
  */
library Addresses {
  // protocol address
    address public constant unitroller = 0xeed247Ba513A8D6f78BE9318399f5eD1a4808F8e;
      // GMX Addresses (when changes to these occur new logic for handling has been historically required)
    address public constant glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    address public constant stakedGlp = 0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE;
    address public constant glpRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public constant fsGLP = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
    address public constant glpVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    address public constant sequencerFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    address public constant swapRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
  }


