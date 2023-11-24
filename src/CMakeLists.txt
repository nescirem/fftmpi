aux_source_directory(./ SRC_LIST)
add_library(fftmpi STATIC ${SRC_LIST})
target_include_directories(fftmpi PUBLIC 
    ${fftmpi_SOURCE_DIR}/include/fftmpi 
    ${fftmpi_SOURCE_DIR}/include/kissfft
)
