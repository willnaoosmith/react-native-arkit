//
//  RCTARSixDegreesMeshController.m
//  RCTARKit
//
//  Created by H. Cole Wiley on 1/16/19.
//  Copyright © 2019 HippoAR. All rights reserved.
//

#import "RCTARSixDegreesMeshController.h"


#import "RCTARKitIO.h"
#import "RCTARKitNodes.h"
#import "RCTConvert+ARKit.h"

#import <SixDegreesSDK/SixDegreesSDK.h>
#import <SixDegreesSDK/SixDegreesSDK_advanced.h>

@implementation RCTARSixDegreesMeshController

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(mount:(NSDictionary *)property
                  node:(SCNNode *)node
                  frame:(NSString *)frame
                  parentId:(NSString *)parentId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject
                  ) {

  // we need to mount first, otherwise, if the loading of the model is slow, it will be registered too late
  [[RCTARKitNodes sharedInstance] addNodeToScene:node inReferenceFrame:frame withParentId:parentId];

  NSDictionary* materialJson;
  if(property[@"material"] ) {
    materialJson = property[@"material"];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    RCTARSixDegreesMeshController* me = [RCTARSixDegreesMeshController sharedInstance];
    if(materialJson) {
      [RCTConvert setMaterialProperties:me.meshMaterial properties:materialJson];
    }

    [node addChildNode:me.matNode];

    if( me.meshNode ){
      [node addChildNode:me.meshNode];
    }
  });
  resolve(nil);
}

+ (instancetype)sharedInstance {
  static RCTARSixDegreesMeshController *instance = nil;
  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    if (instance == nil) {
      instance = [[self alloc] init];
    }
  });
  return instance;
}


- (instancetype)init {
  self = [super init];
  if (self) {
    _meshMaterial = [SCNMaterial new];
    [_meshMaterial setName:@"SixDegreesMeshMaterial"];
//    [_meshMaterial setDoubleSided:YES];
//    _meshMaterial.diffuse.contents = [UIColor colorWithWhite:0.6f alpha:0.5f];

    SCNGeometry* geometry = [SCNGeometry geometry];
    _matNode = [SCNNode nodeWithGeometry:geometry];
    [_matNode setName:@"SixDegreesMatNode"];
    [_meshNode setRenderingOrder:-20];
    _matNode.geometry.firstMaterial = _meshMaterial;
//    [SCNMaterial new];
//    _matNode.geometry.firstMaterial.doubleSided = true;
//    _matNode.geometry.firstMaterial.diffuse.contents = [UIColor colorWithWhite:0.6f alpha:0.5f];

    _meshNode = [SCNNode new];
    [_meshNode setName:@"SixDegreesMesh"];
    [_meshNode setRenderingOrder:-10];

    //      _meshMaterial.writesToDepthBuffer = true;
    //      _meshMaterial.readsFromDepthBuffer = true;
    //      _meshMaterial.colorBufferWriteMask = SCNColorMaskNone;
    //        [_meshMaterial setShaderModifiers:
    //  @{ SCNShaderModifierEntryPointSurface:
    //         @"float4 surfaceNormal = float4(_surface.normal, 0.0f);"
    //     "float4 normal = scn_frame.inverseViewTransform * surfaceNormal;"
    //     "_surface.diffuse.xyz = abs(normal.xyz);" }];
    _meshVersion = -1;
  }
  return self;
}

- (SCNNode*) node {
  return _meshNode;
}

- (void)update {
  if( SixDegreesSDK_IsInitialized() ){
    int blockBufferSize = 0;
    int vertexBufferSize = 0;
    int faceBufferSize = 0;
    int newVersion = SixDegreesSDK_GetMeshBlockInfo(&blockBufferSize, &vertexBufferSize, &faceBufferSize);

    if (newVersion > _meshVersion) {
      if (blockBufferSize <= 0 ||
          vertexBufferSize <= 0 ||
          faceBufferSize <= 0) {
        return;
      }

      int* blockBuffer = (int*)malloc(blockBufferSize*sizeof(int));
      float* vertexBuffer = (float*)malloc(vertexBufferSize*sizeof(float));
      int* faceBuffer = (int*)malloc(faceBufferSize*sizeof(int));

      int fullBlocks = SixDegreesSDK_GetMeshBlocks(blockBuffer, vertexBuffer, faceBuffer,
                                                   blockBufferSize, vertexBufferSize, faceBufferSize);
      if (fullBlocks <= 0) {
        NSLog(@"SixDegreesSDK_GetMeshBlocks() gave us an empty mesh, will not update.");
        return;
      }

      if (fullBlocks != blockBufferSize / 6) {
        NSLog(@"SixDegreesSDK_GetMeshBlocks() returned %d full blocks, expected %d", fullBlocks, (blockBufferSize / 6));
      }

      _meshVersion = newVersion;

      int vertexCount = vertexBufferSize / 6;
      SCNVector3* vertices = malloc(vertexCount*sizeof(SCNVector3));
      SCNVector3* normals = malloc(vertexCount*sizeof(SCNVector3));
      for (int i = 0; i < vertexCount; i++) {
        vertices[i] = SCNVector3Make(vertexBuffer[6*i], vertexBuffer[6*i+1], vertexBuffer[6*i+2]);
        normals[i] = SCNVector3Make(vertexBuffer[6*i+3], vertexBuffer[6*i+4], vertexBuffer[6*i+5]);
      }
      int faceCount = faceBufferSize / 3;
      NSData* faces = [NSData dataWithBytes:faceBuffer
                                     length:sizeof(int)*faceBufferSize];

      SCNGeometrySource* vertexSource = [SCNGeometrySource geometrySourceWithVertices:vertices
                                                                                count:vertexCount];
      SCNGeometrySource* normalSource = [SCNGeometrySource geometrySourceWithNormals:normals
                                                                               count:vertexCount];
      SCNGeometryElement* element = [SCNGeometryElement geometryElementWithData:faces
                                                                  primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                                 primitiveCount:faceCount
                                                                  bytesPerIndex:sizeof(int)];
      SCNGeometry* geometry = [SCNGeometry geometryWithSources:@[vertexSource, normalSource]
                                                      elements:@[element]];
      [geometry setWantsAdaptiveSubdivision:NO];
      if( _matNode && _matNode.geometry.firstMaterial ){
        [geometry setFirstMaterial:_matNode.geometry.firstMaterial];
        _meshMaterial = _matNode.geometry.firstMaterial;
      } else {
        [geometry setFirstMaterial:_meshMaterial];
      }
      [_meshNode setGeometry:geometry];
      _meshNode.physicsBody = [SCNPhysicsBody
                               bodyWithType:SCNPhysicsBodyTypeStatic
                               shape:[SCNPhysicsShape
                                      shapeWithGeometry:geometry
                                      options:@{
                                                SCNPhysicsShapeKeepAsCompoundKey: @TRUE,
                                                SCNPhysicsShapeTypeKey: SCNPhysicsShapeTypeConcavePolyhedron,
                                                }
                                      ]
                               ];

      free(blockBuffer);
      free(vertexBuffer);
      free(faceBuffer);
      free(vertices);
      free(normals);
    } else if (newVersion == 0 && _meshVersion > 0) {
      _meshVersion = 0;
    }
  }
}

@end