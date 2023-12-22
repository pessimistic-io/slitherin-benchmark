// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { LibUtil } from "./LibUtil.sol";
import { IERC20Decimals } from "./IERC20Decimals.sol";

library LibFeeCollector {
    bytes32 internal constant FEE_STORAGE_POSITION =
        keccak256("fee.collector.storage.position");

    struct FeeStorage {
        address mainPartner;
        uint256 mainFee; //1-10000
        uint256 defaultPartnerFeeShare;
        mapping(address => bool) isPartner;
        mapping(address => uint256) partnerFeeSharePercent; //1 - 10000;
        //partner -> token -> amount
        mapping(address => mapping(address => uint256)) feePerToken;
    }

    function _getStorage()
        internal
        pure
        returns (FeeStorage storage fs)
    {
        bytes32 position = FEE_STORAGE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            fs.slot := position
        }
    }

    function updateMainPartner(address _mainPartner) internal {
        FeeStorage storage fs = _getStorage();

        fs.mainPartner = _mainPartner;
    }

    function updateMainFee(uint256 _mainFee) internal {
        FeeStorage storage fs = _getStorage();

        fs.mainFee = _mainFee;
    }

    function addPartner(address _partner, uint256 _partnerFeeShare) internal {
        FeeStorage storage fs = _getStorage();

        fs.isPartner[_partner] = true;
        fs.partnerFeeSharePercent[_partner] = _partnerFeeShare;
    }

    function removePartner(address _partner) internal {
        FeeStorage storage fs = _getStorage();
        if (!fs.isPartner[_partner]) return;

        fs.isPartner[_partner] = false;
        fs.partnerFeeSharePercent[_partner] = 0;
    }

    function getMainFee() internal view returns (uint256) {
        return _getStorage().mainFee;
    }

    function getMainPartner() internal view returns (address) {
        return _getStorage().mainPartner;
    }

    function getPartnerInfo(address _partner) internal view returns (bool isPartner, uint256 partnerFeeSharePercent) {
        FeeStorage storage fs = _getStorage();
        return (fs.isPartner[_partner], fs.partnerFeeSharePercent[_partner]);
    }

    function getFeeAmount(address _token, address _partner) internal view returns (uint256) {
        return(_getStorage().feePerToken[_partner][_token]);
    }

    function decreaseFeeAmount(uint256 _amount, address _account, address _token) internal {
        FeeStorage storage fs = _getStorage();

        fs.feePerToken[_account][_token] -= _amount;
    } 

    function takeFromTokenFee(uint256 _amount, address _token, address _partner) internal returns (uint256 newAmount) {
        FeeStorage storage fs = _getStorage();

        (uint256 mainFee, uint256 partnerFee) = _calcFees(_amount, _partner);
        registerFee(mainFee, fs.mainPartner, _token);
        if (partnerFee != 0) registerFee(partnerFee, _partner, _token);
        
        newAmount = _amount - (mainFee + partnerFee);
    }

    function takeCrosschainFee(
        uint256 _amount,
        address _partner,
        address _token,
        uint256 _crosschainFee,
        uint256 _minFee
    ) internal returns (uint256 newAmount) {
        FeeStorage storage fs = _getStorage();

        (uint256 mainFee, uint256 partnerFee) = _calcCrosschainFees(_amount, _crosschainFee, _minFee, _token, _partner);
        registerFee(mainFee, fs.mainPartner, _token);
        if (partnerFee != 0) registerFee(partnerFee, _partner, _token);
        
        newAmount = _amount - (mainFee + partnerFee);
    }  

    function _calcFees(uint256 _amount, address _partner) private view returns (uint256, uint256){
        FeeStorage storage fs = _getStorage();
        uint256 totalFee = _amount * fs.mainFee / 10000;

        return _splitFee(totalFee, _partner);
    }

    function _calcCrosschainFees(
        uint256 _amount, 
        uint256 _crosschainFee, 
        uint256 _minFee, 
        address _token,
        address _partner
    ) internal view returns (uint256, uint256) {
        uint256 percentFromAmount = _amount * _crosschainFee / 10000;
        
        uint256 decimals = IERC20Decimals(_token).decimals();
        uint256 minFee = _minFee * 10**decimals / 10000;

        uint256 totalFee = percentFromAmount < minFee ? minFee : percentFromAmount;

        return _splitFee(totalFee, _partner);
    }

    function _splitFee(uint256 totalFee, address _partner) private view returns (uint256, uint256) {
        FeeStorage storage fs = _getStorage();

        uint256 mainFee;
        uint256 partnerFee;

        if (LibUtil.isZeroAddress(_partner)) {
            mainFee = totalFee;
            partnerFee = 0;
        } else {
            uint256 partnerFeePercent = fs.isPartner[_partner] 
                ? fs.partnerFeeSharePercent[_partner]
                : fs.defaultPartnerFeeShare;
            partnerFee = totalFee * partnerFeePercent / 10000;
            mainFee = totalFee - partnerFee;
        }  

        return (mainFee, partnerFee);
    }

     function registerFee(uint256 _fee, address _partner, address _token) private {
        FeeStorage storage fs = _getStorage();
        
        fs.feePerToken[_partner][_token] += _fee;
    }
}

