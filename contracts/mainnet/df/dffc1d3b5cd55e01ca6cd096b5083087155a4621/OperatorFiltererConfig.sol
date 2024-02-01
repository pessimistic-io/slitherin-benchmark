// SPDX-License-Identifier: Apache-2.0

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                           //
//                      _'                    AAA                                                                                            //
//                    !jz_                   A:::A                                                                                           //
//                 ;Lzzzz-                  A:::::A                                                                                          //
//              '1zzzzxzz'                 A:::::::A                                                                                         //
//            !xzzzzzzi~                  A:::::::::A             ssssssssss   ppppp   ppppppppp       eeeeeeeeeeee    nnnn  nnnnnnnn        //
//         ;izzzzzzj^`                   A:::::A:::::A          ss::::::::::s  p::::ppp:::::::::p    ee::::::::::::ee  n:::nn::::::::nn      //
//              `;^.`````               A:::::A A:::::A       ss:::::::::::::s p:::::::::::::::::p  e::::::eeeee:::::een::::::::::::::nn     //
//              -;;;;;;;-              A:::::A   A:::::A      s::::::ssss:::::spp::::::ppppp::::::pe::::::e     e:::::enn:::::::::::::::n    //
//           .;;;;;;;_                A:::::A     A:::::A      s:::::s  ssssss  p:::::p     p:::::pe:::::::eeeee::::::e  n:::::nnnn:::::n    //
//         ;;;;;;;;`                 A:::::AAAAAAAAA:::::A       s::::::s       p:::::p     p:::::pe:::::::::::::::::e   n::::n    n::::n    //
//      _;;;;;;;'                   A:::::::::::::::::::::A         s::::::s    p:::::p     p:::::pe::::::eeeeeeeeeee    n::::n    n::::n    //
//            ;{jjjjjjjjj          A:::::AAAAAAAAAAAAA:::::A  ssssss   s:::::s  p:::::p    p::::::pe:::::::e             n::::n    n::::n    //
//         `+IIIVVVVVVVVI`        A:::::A             A:::::A s:::::ssss::::::s p:::::ppppp:::::::pe::::::::e            n::::n    n::::n    //
//       ^sIVVVVVVVVVVVVI`       A:::::A               A:::::As::::::::::::::s  p::::::::::::::::p  e::::::::eeeeeeee    n::::n    n::::n    //
//    ~xIIIVVVVVVVVVVVVVI`      A:::::A                 A:::::As:::::::::::ss   p::::::::::::::pp    ee:::::::::::::e    n::::n    n::::n    //
//  -~~~;;;;;;;;;;;;;;;;;      AAAAAAA                   AAAAAAAsssssssssss     p::::::pppppppp        eeeeeeeeeeeeee    nnnnnn    nnnnnn    //
//                                                                              p:::::p                                                      //
//                                                                              p:::::p                                                      //
//                                                                             p:::::::p                                                     //
//                                                                             p:::::::p                                                     //
//                                                                             p:::::::p                                                     //
//                                                                             ppppppppp                                                     //
//                                                                                                                                           //
//  Website: https://aspenft.io/                                                                                                             //
//  Twitter: https://twitter.com/aspenft                                                                                                     //
//                                                                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

pragma solidity ^0.8;

import "./IOperatorFilterersConfig.sol";
import "./OperatorFiltererDataTypes.sol";
import "./ICoreErrors.sol";

/// @title OperatorFiltererConfig
/// @notice Handles the operator filteres enabled in Aspen Platform.
///         It allows the update and retrieval of platform's operator filters.
contract OperatorFiltererConfig is IOperatorFiltererConfigV0 {
    mapping(bytes32 => IOperatorFiltererDataTypesV0.OperatorFilterer) private _operatorFilterers;
    bytes32[] private _operatorFiltererIds;

    modifier isValidOperatorConfig(IOperatorFiltererDataTypesV0.OperatorFilterer memory _newOperatorFilterer) {
        if (
            _newOperatorFilterer.operatorFiltererId == "" ||
            bytes(_newOperatorFilterer.name).length == 0 ||
            _newOperatorFilterer.defaultSubscription == address(0) ||
            _newOperatorFilterer.operatorFilterRegistry == address(0)
        ) revert IOperatorFiltererConfigErrorsV0.InvalidOperatorFiltererDetails();
        _;
    }

    function getOperatorFiltererOrDie(bytes32 _operatorFiltererId)
        public
        view
        returns (IOperatorFiltererDataTypesV0.OperatorFilterer memory)
    {
        if (_operatorFilterers[_operatorFiltererId].defaultSubscription == address(0))
            revert IOperatorFiltererConfigErrorsV0.OperatorFiltererNotFound();
        return _operatorFilterers[_operatorFiltererId];
    }

    function getOperatorFilterer(bytes32 _operatorFiltererId)
        public
        view
        returns (IOperatorFiltererDataTypesV0.OperatorFilterer memory)
    {
        return _operatorFilterers[_operatorFiltererId];
    }

    function getOperatorFiltererIds() public view returns (bytes32[] memory operatorFiltererIds) {
        operatorFiltererIds = _operatorFiltererIds;
    }

    function addOperatorFilterer(IOperatorFiltererDataTypesV0.OperatorFilterer memory _newOperatorFilterer)
        public
        virtual
        isValidOperatorConfig(_newOperatorFilterer)
    {
        _addOperatorFilterer(_newOperatorFilterer);
    }

    function _addOperatorFilterer(IOperatorFiltererDataTypesV0.OperatorFilterer memory _newOperatorFilterer) internal {
        _operatorFiltererIds.push(_newOperatorFilterer.operatorFiltererId);
        _operatorFilterers[_newOperatorFilterer.operatorFiltererId] = _newOperatorFilterer;

        emit OperatorFiltererAdded(
            _newOperatorFilterer.operatorFiltererId,
            _newOperatorFilterer.name,
            _newOperatorFilterer.defaultSubscription,
            _newOperatorFilterer.operatorFilterRegistry
        );
    }
}

