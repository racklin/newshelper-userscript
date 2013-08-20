// Generated by LiveScript 1.2.0
(function(){
  module.exports = function(grunt){
    grunt.task.loadNpmTasks('grunt-lsc');
    grunt.task.loadNpmTasks('grunt-contrib-uglify');
    grunt.task.loadNpmTasks('grunt-contrib-concat');
    grunt.initConfig({
      lsc: {
        user: {
          files: {
            'user.js': ['user.ls']
          }
        }
      },
      concat: {
        user: {
          files: {
            'user.js': ['meta.js', 'user.js'],
            'user.min.js': ['meta.js', 'user.min.js']
          }
        }
      },
      uglify: {
        user: {
          options: {
            preserveComments: 'some'
          },
          files: {
            'user.min.js': ['user.js']
          }
        }
      }
    });
    return grunt.registerTask('default', ['lsc', 'uglify', 'concat']);
  };
}).call(this);