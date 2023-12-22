
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./DAOAccessControlled.sol";
import "./IDispatcher.sol";
import "./IDispatcherHelper.sol";
import "./ICollectionManager.sol";
import "./Initializable.sol";

contract DispatcherHelper is IDispatcherHelper, Initializable, DAOAccessControlled {
    
    address public dispatcher;

    function initialize(
        address _authority,
        address _dispatcher
    ) public initializer {

        DAOAccessControlled._setAuthority(_authority);
        dispatcher = _dispatcher;

    }

    function getAllActiveReservations() external view returns(IDispatcher.Reservation[] memory _activeReservations) {

        uint256 currentReservationId = IDispatcher(dispatcher).getCurrentReservationId();
        IDispatcher.Reservation[] memory reservations = IDispatcher(dispatcher).getAllReservations();

        uint256 count;
        for (uint256 i = 0; i < currentReservationId; i++) {
            if (
                reservations[i].expiry > block.timestamp &&
                !reservations[i].cancelled &&
                !reservations[i].fulfilled
            ) {
                count++;
            }
        }
        
        uint256 j;
        _activeReservations = new IDispatcher.Reservation[](count);

        for(uint256 i = 0; i < currentReservationId; i++) {
            if(
                reservations[i].expiry > block.timestamp &&
                !reservations[i].cancelled &&
                !reservations[i].fulfilled
            ) {
                _activeReservations[j] = reservations[i];
                j++;
            }
        }

    }

    function getPatronReservations(address _patron, bool _checkActive) external view returns(IDispatcher.Reservation[] memory _patronReservations) {
        
        uint256 currentReservationId = IDispatcher(dispatcher).getCurrentReservationId();
        IDispatcher.Reservation[] memory reservations = IDispatcher(dispatcher).getAllReservations();

        uint256 count;
        for (uint256 i = 0; i < currentReservationId; i++) {
            if(reservations[i].patron == _patron) {
                if(
                    _checkActive && 
                    reservations[i].expiry > block.timestamp &&
                    !reservations[i].cancelled &&
                    !reservations[i].fulfilled 
                ) {
                    count++;
                } else if ( !_checkActive ) {
                    count++;
                }
            }
        }
        
        uint256 j;
        _patronReservations = new IDispatcher.Reservation[](count);
        
        for(uint256 i = 0; i < currentReservationId; i++) {
            if(reservations[i].patron == _patron) {
                if(
                    _checkActive && 
                    reservations[i].expiry > block.timestamp &&
                    !reservations[i].cancelled &&
                    !reservations[i].fulfilled 
                ) {
                    _patronReservations[j] = reservations[i];
                    j++;
                } else if( !_checkActive ) {
                    _patronReservations[j] = reservations[i];
                    j++;
                }
            }
        }

    }

    function patronReservationActiveForOffer(address _patron, address _offer) external view returns(bool) {
        
        IDispatcher.Reservation[] memory reservations = IDispatcher(dispatcher).getAllReservations();

        uint256 patronOfferRecentReservation = IDispatcher(dispatcher).getPatronRecentReservationForOffer(_patron, _offer);

        return (
            reservations[patronOfferRecentReservation].expiry > block.timestamp &&
            !reservations[patronOfferRecentReservation].fulfilled &&
            !reservations[patronOfferRecentReservation].cancelled
        );

    }

    function getActiveReservationsForEntity(address _entity) external view returns(IDispatcher.Reservation[] memory _entityActiveReservations) {

        IDispatcher.Reservation[] memory reservations = IDispatcher(dispatcher).getAllReservations();
        
        address[] memory offerList = IDispatcher(dispatcher).getAllOffers();

        uint256 count;

        for(uint256 i = 0; i < offerList.length; i++) {

            address offer = offerList[i];

            uint256[] memory reservationIdsListForOffer = IDispatcher(dispatcher).getReservationsForOffer(offer);
            
            if(ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(offer).entity == _entity) {
                                
                for(uint256 j = 0; j < reservationIdsListForOffer.length; j++) {
                    if(
                        reservations[reservationIdsListForOffer[j]].expiry > block.timestamp &&
                        !reservations[reservationIdsListForOffer[j]].fulfilled &&
                        !reservations[reservationIdsListForOffer[j]].cancelled
                    ) {
                        count++;
                    }
                }
            }
        }

        uint256 k;
        _entityActiveReservations = new IDispatcher.Reservation[](count);

        for(uint256 i = 0; i < offerList.length; i++) {
            
            address offer = offerList[i];

            uint256[] memory reservationIdsListForOffer = IDispatcher(dispatcher).getReservationsForOffer(offer);
            
            if(ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(offer).entity == _entity) {
                                
                for(uint256 j = 0; j < reservationIdsListForOffer.length; j++) {
                    if(
                        reservations[reservationIdsListForOffer[j]].expiry > block.timestamp &&
                        !reservations[reservationIdsListForOffer[j]].fulfilled &&
                        !reservations[reservationIdsListForOffer[j]].cancelled
                    ) {

                        _entityActiveReservations[k] = reservations[reservationIdsListForOffer[j]];
                        k++;

                    }
                }
            }
        }
    }
}
