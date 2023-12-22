// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SD59x18.sol";
import "./Utils.sol";

library PageRank {
    function normalizeMatrix(
        SD59x18[][] memory matrix
    ) private pure returns (SD59x18[][] memory normalized) {
        // slither-disable-start similar-names
        SD59x18[] memory columnsSums = new SD59x18[](matrix.length);
        normalized = new SD59x18[][](matrix.length);
        bool[] memory columnIndexesWithOnlyZeros = new bool[](matrix.length);

        // Dealing with dangling nodes (nodes that have no outgoing edge)
        for (
            uint256 columnIndex = 0;
            columnIndex < matrix[0].length;
            columnIndex++
        ) {
            bool hasOnlyZeroes = true;
            for (uint256 rowIndex = 0; rowIndex < matrix.length; rowIndex++) {
                if (!eq(matrix[rowIndex][columnIndex], sd(0))) {
                    hasOnlyZeroes = false;
                    columnsSums[columnIndex] = columnsSums[columnIndex].add(
                        matrix[rowIndex][columnIndex]
                    );
                }
            }
            columnIndexesWithOnlyZeros[columnIndex] = hasOnlyZeroes;
        }

        for (uint256 k = 0; k < columnIndexesWithOnlyZeros.length; k++) {
            if (columnIndexesWithOnlyZeros[k]) {
                for (
                    uint256 rowIndex = 0;
                    rowIndex < matrix.length;
                    rowIndex++
                ) {
                    matrix[rowIndex][k] = sd(1e18);
                    columnsSums[k] = columnsSums[k].add(sd(1e18));
                }
            }
        }

        for (uint256 rowIndex = 0; rowIndex < matrix.length; rowIndex++) {
            SD59x18[] memory line = new SD59x18[](matrix.length);
            for (
                uint256 columnIndex = 0;
                columnIndex < matrix[0].length;
                columnIndex++
            ) {
                line[columnIndex] = matrix[rowIndex][columnIndex].div(
                    columnsSums[columnIndex]
                );
            }
            normalized[rowIndex] = line;
        }

        return normalized;
        // slither-disable-end similar-names
    }

    function computeMHat(
        SD59x18[][] memory matrix,
        SD59x18 d,
        int256 numberOfHunters
    ) private pure returns (SD59x18[][] memory mHat) {
        SD59x18 one = sd(1e18);
        mHat = new SD59x18[][](matrix.length);
        // M_hat = (d * M + (1 - d) / N)
        for (uint256 rowIndex = 0; rowIndex < matrix.length; rowIndex++) {
            SD59x18[] memory line = new SD59x18[](matrix.length);
            for (
                uint256 columnIndex = 0;
                columnIndex < matrix[0].length;
                columnIndex++
            ) {
                line[columnIndex] = matrix[rowIndex][columnIndex].mul(d).add(
                    (one.sub(d)).div(convert(numberOfHunters))
                );
            }
            mHat[rowIndex] = line;
        }

        return mHat;
    }

    // Inspired by https://github.com/NTA-Capital/SolMATe/blob/main/contracts/MatrixUtils.sol#L61-L77
    function dot(
        SD59x18[][] memory a,
        SD59x18[][] memory b
    ) internal pure returns (SD59x18[][] memory) {
        uint256 l1 = a.length;
        uint256 l2 = b[0].length;
        uint256 zipsize = b.length;
        SD59x18[][] memory c = new SD59x18[][](l1);
        for (uint256 fi = 0; fi < l1; fi++) {
            c[fi] = new SD59x18[](l2);
            for (uint256 fj = 0; fj < l2; fj++) {
                SD59x18 entry = sd(0e18);
                for (uint256 i = 0; i < zipsize; i++) {
                    entry = entry.add(a[fi][i].mul(b[i][fj]));
                }
                c[fi][fj] = entry;
            }
        }
        return c;
    }

    function weightedPagerank(
        int256[][] memory weightMatrix,
        SD59x18 d
    ) external pure returns (SD59x18[] memory score, bool hasConverged) {
        // Switching to float numbers
        SD59x18[][] memory matrix = new SD59x18[][](weightMatrix.length);

        for (uint256 index = 0; index < weightMatrix.length; index++) {
            SD59x18[] memory line = new SD59x18[](weightMatrix.length);
            for (
                uint256 jindex = 0;
                jindex < weightMatrix[index].length;
                jindex++
            ) {
                line[jindex] = convert(weightMatrix[index][jindex]);
            }
            matrix[index] = line;
        }

        uint256 maxIter = 100;
        SD59x18 tol = sd(1e12);

        // Normalize
        // matrix /= np.sum(matrix, axis=0)
        matrix = normalizeMatrix(matrix);

        // Initialization
        // v = np.ones(N) / N
        int256 numberOfHunters = int256(matrix[0].length);
        SD59x18[] memory v = new SD59x18[](matrix[0].length);
        for (int256 m = 0; m < numberOfHunters; m++) {
            v[uint256(m)] = sd(1e18).div(convert(numberOfHunters));
        }

        // Loop
        hasConverged = false;
        SD59x18[][] memory mHat = computeMHat(matrix, d, numberOfHunters);

        for (uint256 n = 0; n < maxIter; n++) {
            SD59x18[] memory vLast = new SD59x18[](v.length);
            for (uint256 o = 0; o < v.length; o++) {
                vLast[o] = v[o];
            }

            // v = M_hat @ v
            SD59x18[][] memory vAsMatrix = new SD59x18[][](v.length);
            for (uint256 p = 0; p < v.length; p++) {
                vAsMatrix[p] = new SD59x18[](1);
                vAsMatrix[p][0] = v[p];
            }
            SD59x18[][] memory dotTemp = dot(mHat, vAsMatrix);
            for (uint256 q = 0; q < dotTemp.length; q++) {
                v[q] = dotTemp[q][0];
            }
            // err = np.linalg.norm(v - v_last)
            // vDiff = v - v_last
            SD59x18[] memory vDiff = new SD59x18[](v.length);
            for (uint256 index = 0; index < v.length; index++) {
                vDiff[index] = v[index].sub(vLast[index]);
            }
            // err = np.linalg.norm(vDiff)
            SD59x18 total = convert(0e18);
            for (uint256 i = 0; i < vDiff.length; i++) {
                total = total.add(vDiff[i].mul(vDiff[i]));
            }
            SD59x18 err = total.sqrt();

            if (lt(err, convert(numberOfHunters).mul(tol))) {
                hasConverged = true;
                break;
            }
        }

        return (v, hasConverged);
    }
}

