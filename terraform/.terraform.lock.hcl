# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.28.0"
  constraints = "6.28.0"
  hashes = [
    "h1:pAg//+BvaDrvVtw5xgijtsKXAYQGLn2mKl0LBUf6aO8=",
    "zh:0ba0d5eb6e0c6a933eb2befe3cdbf22b58fbc0337bf138f95bf0e8bb6e6df93e",
    "zh:23eacdd4e6db32cf0ff2ce189461bdbb62e46513978d33c5de4decc4670870ec",
    "zh:307b06a15fc00a8e6fd243abde2cbe5112e9d40371542665b91bec1018dd6e3c",
    "zh:37a02d5b45a9d050b9642c9e2e268297254192280df72f6e46641daca52e40ec",
    "zh:3da866639f07d92e734557d673092719c33ede80f4276c835bf7f231a669aa33",
    "zh:480060b0ba310d0f6b6a14d60b276698cb103c48fd2f7e2802ae47c963995ec6",
    "zh:57796453455c20db80d9168edbf125bf6180e1aae869de1546a2be58e4e405ec",
    "zh:69139cba772d4df8de87598d8d8a2b1b4b254866db046c061dccc79edb14e6b9",
    "zh:7312763259b859ff911c5452ca8bdf7d0be6231c5ea0de2df8f09d51770900ac",
    "zh:8d2d6f4015d3c155d7eb53e36f019a729aefb46ebfe13f3a637327d3a1402ecc",
    "zh:94ce589275c77308e6253f607de96919b840c2dd36c44aa798f693c9dd81af42",
    "zh:9b12af85486a96aedd8d7984b0ff811a4b42e3d88dad1a3fb4c0b580d04fa425",
    "zh:adaceec6a1bf4f5df1e12bd72cf52b72087c72efed078aef636f8988325b1a8b",
    "zh:d37be1ce187d94fd9df7b13a717c219964cd835c946243f096c6b230cdfd7e92",
    "zh:fe6205b5ca2ff36e68395cb8d3ae10a3728f405cdbcd46b206a515e1ebcf17a1",
  ]
}

provider "registry.terraform.io/hashicorp/time" {
  version     = "0.12.1"
  constraints = "0.12.1"
  hashes = [
    "h1:VgFDnbNB6f13IXMkO9dRNNkcJFk0/SOM0e82qhO1e8I=",
    "zh:090023137df8effe8804e81c65f636dadf8f9d35b79c3afff282d39367ba44b2",
    "zh:26f1e458358ba55f6558613f1427dcfa6ae2be5119b722d0b3adb27cd001efea",
    "zh:272ccc73a03384b72b964918c7afeb22c2e6be22460d92b150aaf28f29a7d511",
    "zh:438b8c74f5ed62fe921bd1078abe628a6675e44912933100ea4fa26863e340e9",
    "zh:78d5eefdd9e494defcb3c68d282b8f96630502cac21d1ea161f53cfe9bb483b3",
    "zh:85c8bd8eefc4afc33445de2ee7fbf33a7807bc34eb3734b8eefa4e98e4cddf38",
    "zh:98bbe309c9ff5b2352de6a047e0ec6c7e3764b4ed3dfd370839c4be2fbfff869",
    "zh:9c7bf8c56da1b124e0e2f3210a1915e778bab2be924481af684695b52672891e",
    "zh:d2200f7f6ab8ecb8373cda796b864ad4867f5c255cff9d3b032f666e4c78f625",
    "zh:d8c7926feaddfdc08d5ebb41b03445166df8c125417b28d64712dccd9feef136",
    "zh:e2412a192fc340c61b373d6c20c9d805d7d3dee6c720c34db23c2a8ff0abd71b",
    "zh:e6ac6bba391afe728a099df344dbd6481425b06d61697522017b8f7a59957d44",
  ]
}

# The integrations/github provider entry is intentionally removed so
# CI's `terraform init` populates a fresh entry matching the 6.12.1
# constraint declared in versions.tf. Reinstate after the next green
# CI run by copying the regenerated block back into source control.
