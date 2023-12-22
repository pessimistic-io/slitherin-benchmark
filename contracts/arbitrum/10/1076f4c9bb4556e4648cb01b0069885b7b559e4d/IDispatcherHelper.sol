// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./IDispatcher.sol";

interface IDispatcherHelper {

    function getAllActiveReservations() external view returns(IDispatcher.Reservation[] memory _activeReservations);
    
    function getPatronReservations(address _patron, bool _checkActive) external view returns(IDispatcher.Reservation[] memory _patronReservations);

    function patronReservationActiveForOffer(address _patron, address _offer) external view returns(bool);

    function getActiveReservationsForEntity(address _entity) external view returns(IDispatcher.Reservation[] memory _entityActiveReservations);

}
