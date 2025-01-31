/** @file bsg_tilegroup.h
 *  @brief Functions and definitions for working with manycore tile groups
 */
#ifndef _BSG_TILEGROUP_H
#define _BSG_TILEGROUP_H

#include "bsg_set_tile_x_y.h"
#include "bsg_manycore.h"

#define STRIPE __attribute__((address_space(1)))

// Passed from linker -- indicates start of striped arrays in DMEM
extern unsigned _bsg_striped_data_start;

/* NOTE: It's usually a cardinal sin to include code in header files, but LLVM
 * needs the definitions of runtime functions avaliable so that the pass can
 * replace loads and stores -- these aren't avaliable via declarations. */

// Load the initializer from an external array in DRAM into tiles
void load_extern_array(int STRIPE *dest_ptr, int *src_ptr, unsigned num_elems, unsigned elem_size) {
    unsigned start_ptr = (unsigned) &_bsg_striped_data_start;
    unsigned ptr = (unsigned) dest_ptr;
    unsigned index = (ptr - start_ptr) / elem_size;
    unsigned local_addr = start_ptr + (index / bsg_group_size) * elem_size;
    int *dest = (int *) local_addr;
    src_ptr += bsg_id;
    for (int i = 0; i < num_elems * (elem_size / sizeof(int)); i++) {
        *dest = *src_ptr;
        src_ptr += bsg_group_size;
        dest++;
    }
}

static int *get_ptr_val(void STRIPE *arr_ptr, unsigned elem_size, unsigned local_offset) {
    unsigned start_ptr = (unsigned) &_bsg_striped_data_start;
    unsigned ptr = (unsigned) arr_ptr;

    // We only need to care about the offset from the start of the .striped.data
    // section. Since data is aligned on word_size * G, we can calculate the
    // "index" into the overall .striped.data segment. In hardware, this would
    // be the same as caluclating the offset from a segment register
    unsigned index = (ptr - start_ptr) / elem_size;
    unsigned local_addr = start_ptr + (index / bsg_group_size) * elem_size;
    // We use local_offset to index into structs, since we stripe entire
    // structs instead of striping words
    local_addr += local_offset;

    // Get X & Y coordinates of the tile that holds the memory address
    unsigned core_id = index % bsg_group_size;
    unsigned tile_x = core_id / bsg_tiles_X;
    unsigned tile_y = core_id % bsg_tiles_X;

    // Construct the remote NPA: 01YY_YYYY_XXXX_XXPP_PPPP_PPPP_PPPP_PPPP
    unsigned remote_ptr_val = REMOTE_EPA_PREFIX << REMOTE_EPA_MASK_SHIFTS |
                              tile_x << X_CORD_SHIFTS |
                              tile_y << Y_CORD_SHIFTS |
                              local_addr;

#ifdef TILEGROUP_DEBUG
    bsg_printf("ID = %u, index = %u; striped_data_start = 0x%x\n",
            core_id, index, &_bsg_striped_data_start);
    bsg_printf("NPA(%d,%d)=(%u, %u, 0x%x, %u)\n", bsg_x, bsg_y, tile_x, tile_y, local_addr, local_offset);
    bsg_printf("Final Pointer(%d,%d) is 0x%x\n", bsg_x, bsg_y, remote_ptr_val);
#endif
    return (int *) remote_ptr_val;;
}

void extern_store_float(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset, float val) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_store_float(0x%x, %d, %d, %x)\n",
            (unsigned) arr_ptr, elem_size, offset, val);
#endif
    float *ptr = (float *) get_ptr_val(arr_ptr, elem_size, offset);
    *ptr = val;
}

void extern_store_int(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset, unsigned val) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_store_int(0x%x, %d, %d, %d)\n",
            (unsigned) arr_ptr, elem_size, offset, val);
#endif
    int *ptr = get_ptr_val(arr_ptr, elem_size, offset);
    *ptr = val;
}


void extern_store_short(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset, short val) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_store_short(0x%x, %d, %d, %d)\n",
            (unsigned) arr_ptr, elem_size, offset, val);
#endif
    short *ptr = (short *) get_ptr_val(arr_ptr, elem_size, offset);
    *ptr = val;
}


void extern_store_char(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset, char val) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_store_char(0x%x, %d, %d, %d)\n",
            (unsigned) arr_ptr, elem_size, offset, val);
#endif
    char *ptr = (char *) get_ptr_val(arr_ptr, elem_size, offset);
    *ptr = val;
}


float extern_load_float(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_load_float(0x%x, %d, %d)\n",
            (unsigned) arr_ptr, elem_size, offset);
#endif
    float *ptr = (float *) get_ptr_val(arr_ptr, elem_size, offset);
    return *ptr;
}

int extern_load_int(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_load_int(0x%x, %d, %d)\n",
            (unsigned) arr_ptr, elem_size, offset);
#endif
    int *ptr = get_ptr_val(arr_ptr, elem_size, offset);
    return *ptr;
}


short extern_load_short(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_load_short(0x%x, %d, %d)\n",
            (unsigned) arr_ptr, elem_size, offset);
#endif
    short *ptr = (short *) get_ptr_val(arr_ptr, elem_size, offset);
    return *ptr;
}


char extern_load_char(int STRIPE *arr_ptr, unsigned elem_size, unsigned offset) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_load_char(0x%x, %d, %d)\n",
            (unsigned) arr_ptr, elem_size, offset);
#endif
    char *ptr = (char *) get_ptr_val(arr_ptr, elem_size, offset);
    return *ptr;
}


void extern_load_memcpy(char *dest, char STRIPE *src, unsigned len) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_load_memcpy(0x%x<-0x%x; %u words)\n",
            dest, src, len);
#endif
    // TODO need offset for structs of structs
    int *src_base = get_ptr_val(src, len, 0);
    int *tdest = (int *) dest;

    while (len) {
        *tdest = *src_base;
        tdest++;
        src_base++;
        len -= sizeof(int);
    }
}


void extern_store_memcpy(char STRIPE *dest, char *src, unsigned len) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_store_memcpy(0x%x<-0x%x; %u words)\n",
            dest, src, len);
#endif

    int *dest_base = get_ptr_val(dest, len, 0);
    int *tsrc = (int *) src;

    while (len) {
        *dest_base = *tsrc;
        dest_base++;
        tsrc++;
        len -= sizeof(int);
    }
}

void extern_memset(char STRIPE *dest, char val, unsigned len) {
#ifdef TILEGROUP_DEBUG
    bsg_printf("\nCalling extern_memset(0x%x<-%x; %u words)\n",
            dest, val, len);
#endif

    char *dest_base = (char *) get_ptr_val(dest, len, 0);

    while (len) {
        *dest_base = val;
        dest_base++;
        len -= sizeof(int);
    }
}

#endif // _BSG_TILEGROUP_H
