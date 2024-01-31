// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Base64.sol";

library PorpRenderer {
    function render(bool hasporpoise) public pure returns (string memory) {
        string memory image = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1080 1080">',
            '<path d="m777.81,638.54s52.35,104.42,140.95,94.22c0,0-15.82-92.69-119.41-124.25" isolation="isolate" opacity=".3"/>',
            '<path d="m781.8,600.52s52.35,104.42,140.95,94.22c0,0-15.82-92.69-119.41-124.25" fill="#fff" stroke="#000" stroke-linecap="round" stroke-miterlimit="10" stroke-width="11.98"/>',
            '<path d="m520.9,513.26c-4.2-51.69,15.72-98.52,49.95-136.61,20.63-22.95,47.52-38.9,77.47-46.28,58.66-14.44,128.4,2.49,162.38,55.38,29.36,45.7,33.63,97.6,21.86,149.66-41.13,181.94-362.06,359.88-544,5.5,0,0-82.27,20.57-131.31-26.9,0,0,60.12-68.03,129.73-47.46,0,0,64.86-106,145.55-110.74,0,0,23.78,83.01-74.35,136.06,0,0,22.63,27.18,81.17,29.84,0,0,40.54-55.66,83.26-55.66" isolation="isolate" opacity=".33"/>',
            '<path d="m520.9,478.87c-4.2-51.69,15.72-98.52,49.95-136.61,20.63-22.95,47.52-38.9,77.47-46.28,58.66-14.44,128.4,2.49,162.38,55.38,29.36,45.7,33.63,97.6,21.86,149.66-41.13,181.94-362.06,359.88-544,5.5,0,0-82.27,20.57-131.31-26.9,0,0,60.12-68.03,129.73-47.46,0,0,64.86-106,145.55-110.74,0,0,23.78,83.01-74.35,136.06,0,0,22.63,27.18,81.17,29.84,0,0,40.54-55.66,83.26-55.66" fill="#fff" stroke="#000" stroke-linecap="round" stroke-miterlimit="10" stroke-width="11.98"/>',
            '<circle cx="610.74" cy="431.31" r="13.48"/>',
            '<circle cx="776.78" cy="434.89" r="13.48"/>',
            '<path d="m617.06,481.02s40.24,16.8,77.34-16.66c0,0,38.99,32.47,75.21,20.24" fill="none" stroke="#000" stroke-linecap="round" stroke-miterlimit="10" stroke-width="11.98"/>',
            '<path d="m665.31,516.16s22.81,22.5,55.41,1.02" fill="none" stroke="#000" stroke-linecap="round" stroke-miterlimit="10" stroke-width="11.98"/>',
            '<path d="m485.98,600.52s-118.53,72.94-96.39,188.43c0,0,112.33-33.22,129.73-167.7" fill="#fff" stroke="#000" stroke-linecap="round" stroke-miterlimit="10" stroke-width="11.98"/>',
            '<line x1="426.89" y1="515.22" x2="439.35" y2="487.31" fill="none" stroke="#000" stroke-linecap="round" stroke-miterlimit="10" stroke-width="11.98"/>',
            "</svg>"
        );

        string memory noImage = string.concat(
            '<svg  xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1080 1080">',
            '<polyline points="299.11 587.88 299.11 270.43 468.66 599.25 452.62 255.58" fill="none" stroke="#000" stroke-miterlimit="10" stroke-width="30"/>',
            '<polygon points="679.44 270.43 558.01 427.76 679.44 587.88 789.41 414.27 679.44 270.43" fill="none" stroke="#000" stroke-miterlimit="10" stroke-width="30"/>',
            "</svg>"
        );

        string memory name = !hasporpoise ? "NO" : "PORPOISE";
        string memory desc = !hasporpoise
            ? "YOU HAVE NO PORPOISE"
            : "YOU HAVE PORPOISE";
        string memory traitValue = !hasporpoise ? "NO" : "YES";
        string memory json = string.concat(
            '{"name":"',
            name,
            '",',
            '"description":"',
            desc,
            '",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(!hasporpoise ? noImage : image)),
            '",',
            '"attributes":[',
            "{",
            '"trait_type":"HAS PORPOISE",',
            '"value":"',
            traitValue,
            '"}]'
            "}"
        );

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            );
    }
}

