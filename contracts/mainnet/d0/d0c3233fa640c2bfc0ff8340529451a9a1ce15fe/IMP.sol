// SPDX-License-Identifier: MIT
/**
 * @dev @brougkr
 */
pragma solidity 0.8.17;
interface IMP 
{ 
    /**
     * @dev { For Instances Where Golden Token Or Artists Have A Bespoke Mint Pass Contract }
     */
    function _LiveMintBurn(uint TicketID) external returns(address Recipient); 

    /**
     * @dev { For Instances Where Artists Share The Same Mint Pass Contract }
     */
    function _LiveMintBurnShared(uint TicketID) external returns(address Recipient, uint ArtistID);
}
