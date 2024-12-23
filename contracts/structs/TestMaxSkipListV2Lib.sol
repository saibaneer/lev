// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library MaxSkipListV2 {
    uint8 constant MAX_LEVEL = 8;
    uint8 constant LEVEL_MASK = uint8((1 << (MAX_LEVEL - 1)) - 1);
    uint256 constant BITMAP_MASK = 0xff;
    uint256 constant PRICE_MASK = ~BITMAP_MASK;

    struct Node {
        uint256 priceAndBitmap;  // Price in upper 248 bits, bitmap in lower 8 bits
        uint256[MAX_LEVEL] packedNextPrev;  // Each element packs next and prev pointers
    }

    struct List {
        uint256 head;
        uint256 highestNodeId;
        uint256 length;
        uint256 nextId;
        uint256 firstFreeId;
        mapping(uint256 => Node) nodes;
        mapping(uint256 => uint256) priceToId;
    }

    event NodeInserted(uint256 indexed nodeId, uint256 price);
    event NodeRemoved(uint256 indexed nodeId, uint256 price);

    // Helper functions for bit manipulation
    function getPrice(uint256 priceAndBitmap) internal pure returns (uint256) {
        return priceAndBitmap >> 8;
    }

    function getLevelBitmap(uint256 priceAndBitmap) internal pure returns (uint8) {
        return uint8(priceAndBitmap & BITMAP_MASK);
    }

    function packPriceAndBitmap(uint256 price, uint8 bitmap) internal pure returns (uint256) {
        return (price << 8) | bitmap;
    }

    function packPointers(uint256 next, uint256 prev) internal pure returns (uint256) {
        return (next << 128) | (prev & ((1 << 128) - 1));
    }

    function unpackPointers(uint256 packed) internal pure returns (uint256 next, uint256 prev) {
        next = packed >> 128;
        prev = packed & ((1 << 128) - 1);
    }

    function getLevel(uint256 nodeId) internal pure returns (uint8) {
        uint256 n = nodeId;
        uint8 level = 0;
        uint256 mask = 1;

        while (level < MAX_LEVEL - 1 && (n & mask) == 0) {
            level++;
            mask <<= 1;
        }
        return level;
    }

    function insert(List storage self, uint256 price) internal returns (uint256 nodeId) {
        require(price > 0 && price < (1 << 248), "Invalid price");
        require(self.priceToId[price] == 0, "Price exists");

        // Get nodeId
        if (self.firstFreeId != 0) {
            nodeId = self.firstFreeId;
            (uint256 next, ) = unpackPointers(self.nodes[nodeId].packedNextPrev[0]);
            self.firstFreeId = next;
        } else {
            nodeId = self.nextId;
            require(nodeId < type(uint128).max, "Too many nodes");
            self.nextId = nodeId + 1;
        }

        uint8 newLevel = getLevel(nodeId);
        uint8 bitmap = uint8((1 << newLevel) - 1);

        // Update highest node if necessary
        if (self.length == 0 || price > getPrice(self.nodes[self.highestNodeId].priceAndBitmap)) {
            self.highestNodeId = nodeId;
        }

        // Initialize new node
        Node storage newNode = self.nodes[nodeId];
        newNode.priceAndBitmap = packPriceAndBitmap(price, bitmap);

        // Find insertion points
        uint256 current = self.head;
        uint256[MAX_LEVEL] memory updates;

        // Fixed the problematic loop
        for (int8 i = int8(MAX_LEVEL) - 1; i >= 0; i--) {
            uint8 level = uint8(i);
            while (true) {
                (uint256 next, ) = unpackPointers(self.nodes[current].packedNextPrev[level]);
                if (next == 0 || getPrice(self.nodes[next].priceAndBitmap) < price) break;
                current = next;
            }
            updates[level] = current;
        }

        // Insert node at each level
        for (uint8 i = 0; i <= newLevel; i++) {
            if ((bitmap & (1 << i)) != 0) {
                uint256 updateNode = updates[i];
                (uint256 next, ) = unpackPointers(self.nodes[updateNode].packedNextPrev[i]);

                // Set new node's pointers
                newNode.packedNextPrev[i] = packPointers(next, updateNode);

                // Update next node's pointers
                if (next != 0) {
                    (uint256 nextNext, ) = unpackPointers(self.nodes[next].packedNextPrev[i]);
                    self.nodes[next].packedNextPrev[i] = packPointers(nextNext, nodeId);
                }

                // Update previous node's pointers
                self.nodes[updateNode].packedNextPrev[i] = packPointers(nodeId, updateNode);
            }
        }

        self.length++;
        self.priceToId[price] = nodeId;
        emit NodeInserted(nodeId, price);
        
        return nodeId;
    }

    function remove(List storage self, uint256 price) internal returns (bool) {
        require(self.length > 0, "Empty list");
        uint256 nodeId = self.priceToId[price];
        require(nodeId != 0, "Price not found");

        Node storage node = self.nodes[nodeId];
        uint256 priceAndBitmap = node.priceAndBitmap;
        uint256 next;
        uint256 prev;

        // If we're removing the highest node, update highestNodeId
        if (nodeId == self.highestNodeId) {
            (next, ) = unpackPointers(node.packedNextPrev[0]);
            self.highestNodeId = next;
        }

        // Remove node from all levels it exists in
        uint8 bitmap = getLevelBitmap(priceAndBitmap);
        for (uint8 i = 0; i < MAX_LEVEL; i++) {
            if ((bitmap & (1 << i)) != 0) {
                (next, prev) = unpackPointers(node.packedNextPrev[i]);
                if (prev != 0) {
                    self.nodes[prev].packedNextPrev[i] = packPointers(next, prev);
                }
                if (next != 0) {
                    self.nodes[next].packedNextPrev[i] = packPointers(next, prev);
                }
            }
        }

        // Add to free list
        node.packedNextPrev[0] = packPointers(self.firstFreeId, 0);
        self.firstFreeId = nodeId;

        delete self.priceToId[getPrice(priceAndBitmap)];
        self.length--;

        emit NodeRemoved(nodeId, getPrice(priceAndBitmap));
        return true;
    }

    function removeHighest(List storage self) internal returns (bool) {
        require(self.length > 0, "Empty list");

        uint256 nodeId = self.highestNodeId;
        Node storage node = self.nodes[nodeId];
        uint256 priceAndBitmap = node.priceAndBitmap;
        uint256 next;
        uint256 prev;

        (next, ) = unpackPointers(node.packedNextPrev[0]);
        self.highestNodeId = next;

        uint8 bitmap = getLevelBitmap(priceAndBitmap);
        for (uint8 i = 0; i < MAX_LEVEL; i++) {
            if ((bitmap & (1 << i)) != 0) {
                (next, prev) = unpackPointers(node.packedNextPrev[i]);
                if (prev != 0) {
                    self.nodes[prev].packedNextPrev[i] = packPointers(next, prev);
                }
                if (next != 0) {
                    self.nodes[next].packedNextPrev[i] = packPointers(next, prev);
                }
            }
        }

        node.packedNextPrev[0] = packPointers(self.firstFreeId, 0);
        self.firstFreeId = nodeId;

        delete self.priceToId[getPrice(priceAndBitmap)];
        self.length--;

        emit NodeRemoved(nodeId, getPrice(priceAndBitmap));
        return true;
    }

    function getHighestPrice(List storage self) internal view returns (uint256) {
        require(self.length > 0, "Empty list");
        return getPrice(self.nodes[self.highestNodeId].priceAndBitmap);
    }

    function initialize(List storage self) internal {
        require(self.head == 0, "Already initialized");
        self.head = 0;
        self.nextId = 1;
        self.firstFreeId = 0;
    }

    function exists(List storage self, uint256 price) internal view returns (bool) {
        return self.priceToId[price] != 0;
    }
}