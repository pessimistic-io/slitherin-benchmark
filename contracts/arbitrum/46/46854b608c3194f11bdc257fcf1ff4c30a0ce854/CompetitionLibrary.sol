pragma solidity ^0.8.12;

import "./IServiceAgreement.sol";
import "./IModeler.sol";
import "./IConsumption.sol";

library CompetitionLibrary {

    function findModelerUpperBound(address[] storage topNModelers, mapping(address => uint256) storage modelerToMedian, uint256 element) external view returns (uint256) {
        if (topNModelers.length == 0) {
            return 0;
        }
        uint256 low = 0;
        uint256 high = topNModelers.length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            uint256 midValue = modelerToMedian[topNModelers[mid]];
            if (element > midValue) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        if (low > 0 && modelerToMedian[topNModelers[low - 1]] == element) {
            return low - 1;
        } else {
            return low;
        }
    }

    function isTopNModeler(address[] storage topNModelers, address _modeler) external view returns (bool isTopN) {
        for (uint256 i = 0; i < topNModelers.length; ++i) {
            if (topNModelers[i] == _modeler) {
                return true;
            }
        }
        return false;
    }
}
