package service

import (
	"context"

	"github.com/NebulaPanel/nebulapanel/agent/buserr"
	"github.com/NebulaPanel/nebulapanel/agent/global"
)

func (v *VMService) deleteVMResource(ctx context.Context, resourceType, name string, force bool) error {
	if err := v.deleteVMResourceWithContext(ctx, resourceType, name); err != nil {
		if !force {
			return err
		}
		if global.LOG != nil {
			global.LOG.Warnf("[xpack] force delete VM %s %q metadata after resource cleanup failed: %v", resourceType, name, err)
		}
	}
	return nil
}

func (v *VMService) deleteVMResourceWithContext(ctx context.Context, resourceType, name string) error {
	if !v.helperExists() {
		return buserr.New("ErrVMHelperNotFound")
	}
	items, err := v.provider.ListResources(ctx, resourceType)
	if err != nil {
		return err
	}
	for _, item := range items {
		if item.Name == name {
			return v.provider.DeleteResource(ctx, resourceType, name)
		}
	}
	return nil
}

