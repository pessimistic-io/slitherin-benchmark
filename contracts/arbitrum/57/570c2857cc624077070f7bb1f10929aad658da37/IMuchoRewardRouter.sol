// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/*
MuchoRewardRouter

Contrato que manejan los rewards de los NFT holders
Guarda liquidez. Un upgrade sería complicado (requeriría una v2 y podría quedar liquidez “muerta” en la v1)
Owner: MuchoHUB

Operaciones de depósito de rewards (público): 
    depositRewards
    withdraw
Operaciones de gestión de usuarios invertidos (owner=MuchoHUB): 
    addUser, removeUser
Operaciones de configuración ó upgrade (protocolOwner): 
    añadir/modificar NFTs suscritos y su multiplicador de APR
    cambiar direcciones de los contratos a los que se conecta

*/

interface IMuchoRewardRouter{
    event UserAdded(address user);
    event UserRemoved(address user);
    event PlanAdded(uint256 planId, uint multiplier);
    event PlanRemoved(uint256 planId);
    event MultiplierChanged(uint256 planId, uint multiplier);
    event RewardsDeposited(address token, uint256 amount);
    event Withdrawn(address token, uint256 amount);
    
    //Checks if a user exists and adds it to the list
    function addUserIfNotExists(address _user) external;
    
    //Removes a user if exists in the lust
    function removeUserIfExists(address _user) external;
    
    //Adds a plan with benefits
    function addPlanId(uint256 _planId, uint _multiplier) external;
    
    //Removes a plan benefits
    function removePlanId(uint256 _planId) external;

    //Changes the multiplier for a plan
    function setMultiplier(uint256 _planId, uint _multiplier) external;
    
    //Deposit the rewards and split among the users
    function depositRewards(address _token, uint256 _amount) external;

    //Withdraws all the rewards the user has
    function withdrawToken(address _token) external returns(uint256);

    //Withdraws all the rewards the user has
    function withdraw() external;

    //For a user, gets the amount ponderation percentage (basis points) for a new deposit. This will be needed to calculate estimated APR of the deposit
    function getUserAmountPonderation(address _user, uint256 _amountUSD) external view returns(uint256);

    //For a plan, gets the current amount ponderation (basis points) for a new deposit. This will be needed to calculate estimated APR that plan's users are getting in avg
    function getPlanPonderation(uint256 _planId) external view returns(uint256);


}
